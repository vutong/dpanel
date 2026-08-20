import { requireAuth } from '../../../utils/auth-guard'
import {
  getActiveScan,
  listScans,
  recordClamavScanEventsIfNeeded,
  resolveClamavScanSummary
} from '../../../utils/clamav-scans'
import { fetchHostSecurityStatus } from '../../../utils/host-security'
import {
  recordSecurityInstallEventIfNeeded,
  resolveSecurityInstallStatus
} from '../../../utils/security-install'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const install = recordSecurityInstallEventIfNeeded('clamav')
    const status = await fetchHostSecurityStatus()

    let detail: {
      version?: string | null
      clamscanPath?: string | null
      clamdscanPath?: string | null
      logPaths?: string[]
    } | null = null

    if (status.clamav?.installed) {
      try {
        const raw = await runScript('host-clamav-detail.sh', [], 90_000)
        detail = parseScriptJson(raw)
      } catch {
        detail = null
      }
    }

    const active = getActiveScan()
    const activeScan = active ? resolveClamavScanSummary(active) : null
    if (activeScan && activeScan.status !== 'running') {
      recordClamavScanEventsIfNeeded(activeScan.id)
    }

    const recentScans = listScans({ limit: 5 }).map((s) => {
      const resolved = resolveClamavScanSummary(s)
      if (resolved.status !== 'running') {
        recordClamavScanEventsIfNeeded(resolved.id)
      }
      return resolved
    })

    return {
      ok: true,
      installed: status.clamav?.installed ?? false,
      daemonActive: status.clamav?.daemonActive ?? false,
      freshclamActive: status.clamav?.freshclamActive ?? false,
      signatureDate: status.clamav?.signatureDate ?? detail?.signatureDate ?? null,
      version: detail?.version ?? null,
      clamscanPath: detail?.clamscanPath ?? null,
      clamdscanPath: detail?.clamdscanPath ?? null,
      logPaths: detail?.logPaths ?? [],
      installStatus: install.status,
      installMessage: install.message ?? '',
      activeScan,
      recentScans
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
        activeScan: null,
        recentScans: []
      }
    }
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
