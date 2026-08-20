import { requireAuth } from '../../../utils/auth-guard'
import { fetchHostSecurityStatus } from '../../../utils/host-security'
import {
  recordSecurityInstallEventIfNeeded,
  resolveSecurityInstallStatus
} from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const install = recordSecurityInstallEventIfNeeded('fail2ban')
    const status = await fetchHostSecurityStatus()
    return {
      ok: true,
      installed: status.fail2ban?.installed ?? false,
      active: status.fail2ban?.active ?? false,
      jails: status.fail2ban?.jails ?? [],
      bannedIps: status.fail2ban?.bannedIps ?? [],
      installStatus: install.status,
      installMessage: install.message ?? ''
    }
  } catch (e: unknown) {
    const install = resolveSecurityInstallStatus('fail2ban')
    if (install.status === 'running') {
      return {
        ok: true,
        installed: false,
        active: false,
        jails: [],
        bannedIps: [],
        installStatus: install.status,
        installMessage: install.message ?? ''
      }
    }
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
