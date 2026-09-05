import { requireAuth } from '../../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled, readCachePayloadWithFallback } from '../../../utils/cache-read'
import { queryClamav, type ClamavQueryResult } from '../../../utils/clamav-host'
import { scriptErrorMessage } from '../../../utils/stack'

type SecurityDetailCachePayload = {
  clamavDetail?: ClamavQueryResult
}

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

export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (!cacheReadEnabled()) {
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
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityDetailCachePayload>(
    'security-detail.json',
    event,
    async () => ({ clamavDetail: await queryClamav('detail') }),
    { sections: ['settings'] }
  )
  const host = payload?.clamavDetail

  if (!host || typeof host !== 'object') {
    const error = result.warming ? 'Warming security detail cache…' : 'Security detail cache unavailable'
    return attachCacheMeta({ ok: false, error, ...emptyDetail() }, result)
  }

  if (!host.installed) {
    return attachCacheMeta(
      { ok: false, error: 'ClamAV is not installed', ...emptyDetail() },
      result
    )
  }

  return attachCacheMeta(
    {
      ok: host.ok !== false,
      installed: host.installed,
      daemonActive: host.daemonActive,
      freshclamActive: host.freshclamActive,
      signatureDate: host.signatureDate,
      version: host.version,
      clamscanPath: host.clamscanPath ?? null,
      clamdscanPath: host.clamdscanPath ?? null,
      logPaths: host.logPaths ?? [],
      ...(host.error ? { error: host.error } : {})
    },
    result
  )
})
