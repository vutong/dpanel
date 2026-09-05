import { requireAuth } from '../../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled, readCachePayloadWithFallback } from '../../../utils/cache-read'
import {
  getActiveScan,
  recordClamavScanEventsIfNeeded,
  resolveClamavScanSummary
} from '../../../utils/clamav-scans'
import { queryClamav, type ClamavQueryResult } from '../../../utils/clamav-host'
import { resolveSecurityInstallStatus } from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

type SecurityCachePayload = {
  clamavSummary?: ClamavQueryResult
}

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const install = resolveSecurityInstallStatus('clamav')
  const active = getActiveScan()
  const activeScan = active ? resolveClamavScanSummary(active) : null
  if (activeScan && activeScan.status !== 'running') {
    recordClamavScanEventsIfNeeded(activeScan.id)
  }

  if (!cacheReadEnabled()) {
    try {
      const host = await queryClamav('summary')
      return {
        ok: true,
        installed: host.installed,
        daemonActive: host.daemonActive,
        freshclamActive: host.freshclamActive,
        signatureDate: host.signatureDate,
        version: host.version,
        installStatus: install.status,
        installMessage: install.message ?? '',
        activeScan
      }
    } catch (e: unknown) {
      if (install.status === 'running') {
        return {
          ok: true,
          installed: false,
          daemonActive: false,
          freshclamActive: false,
          signatureDate: null,
          version: null,
          installStatus: install.status,
          installMessage: install.message ?? '',
          activeScan: null
        }
      }
      const error = scriptErrorMessage(e)
      return {
        ok: false,
        error,
        daemonActive: false,
        freshclamActive: false,
        signatureDate: null,
        version: null,
        installStatus: install.status,
        installMessage: install.message || error,
        activeScan: null
      }
    }
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityCachePayload>(
    'security.json',
    event,
    async () => ({ clamavSummary: await queryClamav('summary') }),
    { sections: ['dashboard', 'settings'] }
  )
  const host = payload?.clamavSummary

  if (host && typeof host === 'object') {
    return attachCacheMeta(
      {
        ok: host.ok !== false,
        installed: host.installed,
        daemonActive: host.daemonActive,
        freshclamActive: host.freshclamActive,
        signatureDate: host.signatureDate,
        version: host.version,
        installStatus: install.status,
        installMessage: install.message ?? '',
        activeScan,
        ...(host.error ? { error: host.error } : {})
      },
      result
    )
  }

  if (install.status === 'running') {
    return attachCacheMeta(
      {
        ok: true,
        installed: false,
        daemonActive: false,
        freshclamActive: false,
        signatureDate: null,
        version: null,
        installStatus: install.status,
        installMessage: install.message ?? '',
        activeScan: null
      },
      result
    )
  }

  const error = result.warming ? 'Warming security cache…' : 'Security cache unavailable'
  return attachCacheMeta(
    {
      ok: false,
      error,
      daemonActive: false,
      freshclamActive: false,
      signatureDate: null,
      version: null,
      installStatus: install.status,
      installMessage: install.message || error,
      activeScan: null
    },
    result
  )
})
