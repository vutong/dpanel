import { requireAuth } from '../../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled, readCachePayloadWithFallback } from '../../../utils/cache-read'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import { enrichFail2banJailsFromSettings, queryFail2ban, type Fail2banQueryResult } from '../../../utils/fail2ban-host'
import { scriptErrorMessage } from '../../../utils/stack'

type SecurityDetailCachePayload = {
  fail2banJails?: Fail2banQueryResult
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  seedFail2banSettingsIfMissing()
  const settings = readFail2banSettings()

  if (!cacheReadEnabled()) {
    try {
      const host = enrichFail2banJailsFromSettings(await queryFail2ban('jails'), settings)
      if (!host.installed) {
        return { ok: false, error: 'Fail2ban is not installed', jails: [], settings }
      }
      const mergedSettings =
        host.global?.ignoreip?.length && settings
          ? { ...settings, ignoreip: host.global.ignoreip }
          : settings
      return {
        ok: true,
        active: host.active,
        global: host.global ?? { ignoreip: mergedSettings.ignoreip },
        jails: host.jails,
        settings: mergedSettings
      }
    } catch (e: unknown) {
      if (e && typeof e === 'object' && 'statusCode' in e) throw e
      return {
        ok: false,
        error: scriptErrorMessage(e),
        jails: [],
        settings
      }
    }
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityDetailCachePayload>(
    'security-detail.json',
    event,
    async () => ({ fail2banJails: await queryFail2ban('jails') }),
    { sections: ['settings'] }
  )
  const host = payload?.fail2banJails

  if (host && typeof host === 'object') {
    const enriched = enrichFail2banJailsFromSettings(host, settings)
    if (!enriched.installed) {
      return attachCacheMeta(
        { ok: false, error: 'Fail2ban is not installed', jails: [], settings },
        result
      )
    }
    const mergedSettings =
      enriched.global?.ignoreip?.length && settings
        ? { ...settings, ignoreip: enriched.global.ignoreip }
        : settings
    return attachCacheMeta(
      {
        ok: enriched.ok !== false,
        active: enriched.active,
        global: enriched.global ?? { ignoreip: mergedSettings.ignoreip },
        jails: enriched.jails,
        settings: mergedSettings,
        ...(enriched.error ? { error: enriched.error } : {})
      },
      result
    )
  }

  const error = result.warming ? 'Warming security detail cache…' : 'Security detail cache unavailable'
  return attachCacheMeta({ ok: false, error, jails: [], settings }, result)
})
