import { requireAuth } from '../../../utils/auth-guard'
import {
  getActiveScan,
  recordClamavScanEventsIfNeeded,
  resolveClamavScanSummary
} from '../../../utils/clamav-scans'
import { queryClamav } from '../../../utils/clamav-host'
import {
  recordSecurityInstallEventIfNeeded,
  resolveSecurityInstallStatus
} from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  try {
    const install = recordSecurityInstallEventIfNeeded('clamav')
    const host = await queryClamav('summary')

    const active = getActiveScan()
    const activeScan = active ? resolveClamavScanSummary(active) : null
    if (activeScan && activeScan.status !== 'running') {
      recordClamavScanEventsIfNeeded(activeScan.id)
    }

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
    const install = resolveSecurityInstallStatus('clamav')
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
