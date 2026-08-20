import { requireAuth } from '../../utils/auth-guard'
import { fetchHostSecurityStatus } from '../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    return await fetchHostSecurityStatus()
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Could not read host security status'
    return {
      ok: false,
      error: msg,
      fail2ban: { installed: false, active: false, jails: [], bannedIps: [] },
      clamav: {
        installed: false,
        daemonActive: false,
        freshclamActive: false,
        signatureDate: null
      }
    }
  }
})
