import { requireAuth } from '../../utils/auth-guard'
import { fetchHostSecurityStatus } from '../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const status = await fetchHostSecurityStatus()
    return {
      ok: true,
      installed: status.fail2ban?.installed ?? false,
      active: status.fail2ban?.active ?? false,
      jails: status.fail2ban?.jails ?? [],
      bannedIps: status.fail2ban?.bannedIps ?? []
    }
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Could not read Fail2ban status'
    })
  }
})
