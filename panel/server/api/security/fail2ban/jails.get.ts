import { requireAuth } from '../../../utils/auth-guard'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import { enrichFail2banJailsFromSettings, queryFail2ban } from '../../../utils/fail2ban-host'
import { scriptErrorMessage } from '../../../utils/stack'

/** Live Fail2ban jails — no cache (settings). */
export default defineEventHandler(async (event) => {
  requireAuth(event)
  seedFail2banSettingsIfMissing()
  const settings = readFail2banSettings()

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
})
