import { requireAuth } from '../../../utils/auth-guard'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import { queryFail2ban } from '../../../utils/fail2ban-host'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  seedFail2banSettingsIfMissing()
  const settings = readFail2banSettings()

  try {
    const host = await queryFail2ban('jails')
    if (!host.installed) {
      return { ok: false, error: 'Fail2ban is not installed', jails: [], settings }
    }

    return {
      ok: true,
      active: host.active,
      global: host.global ?? { ignoreip: settings.ignoreip },
      jails: host.jails,
      settings
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
