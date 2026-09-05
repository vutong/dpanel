import { requireAuth } from '../../../utils/auth-guard'
import {
  getActiveScan,
  recordClamavScanEventsIfNeeded,
  resolveClamavScanSummary
} from '../../../utils/clamav-scans'
import { queryClamav } from '../../../utils/clamav-host'
import { resolveSecurityInstallStatus } from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

/** Live ClamAV summary — no cache (settings / ops). */
export default defineEventHandler(async (event) => {
  requireAuth(event)

  const install = resolveSecurityInstallStatus('clamav')
  const active = getActiveScan()
  const activeScan = active ? resolveClamavScanSummary(active) : null
  if (activeScan && activeScan.status !== 'running') {
    recordClamavScanEventsIfNeeded(activeScan.id)
  }

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
})
