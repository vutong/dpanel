import { requireAuth } from '../../utils/auth-guard'
import type { HostSecurityStatus } from '../../utils/host-security'
import { fetchHostSecurityStatus } from '../../utils/host-security'

const EMPTY: HostSecurityStatus = {
  ok: false,
  fail2ban: { installed: false, active: false, jails: [], bannedIps: [] },
  clamav: {
    installed: false,
    daemonActive: false,
    freshclamActive: false,
    signatureDate: null
  }
}

/** Live host security status — no cache (business / ops). */
export default defineEventHandler(async (event) => {
  requireAuth(event)

  try {
    return await fetchHostSecurityStatus()
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Could not read host security status'
    return { ...EMPTY, error: msg }
  }
})
