import { requireAuth } from '../../../utils/auth-guard'
import { queryClamav } from '../../../utils/clamav-host'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  try {
    const host = await queryClamav('detail')
    if (!host.installed) {
      return { ok: false, error: 'ClamAV is not installed', ...emptyDetail() }
    }

    return {
      ok: true,
      installed: host.installed,
      daemonActive: host.daemonActive,
      freshclamActive: host.freshclamActive,
      signatureDate: host.signatureDate,
      version: host.version,
      clamscanPath: host.clamscanPath ?? null,
      clamdscanPath: host.clamdscanPath ?? null,
      logPaths: host.logPaths ?? []
    }
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e),
      ...emptyDetail()
    }
  }
})

function emptyDetail() {
  return {
    installed: false,
    daemonActive: false,
    freshclamActive: false,
    signatureDate: null,
    version: null,
    clamscanPath: null,
    clamdscanPath: null,
    logPaths: [] as string[]
  }
}
