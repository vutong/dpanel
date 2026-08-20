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
      throw createError({ statusCode: 400, statusMessage: 'Fail2ban is not installed' })
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
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
