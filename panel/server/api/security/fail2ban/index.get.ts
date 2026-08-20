import { requireAuth } from '../../../utils/auth-guard'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import {
  queryFail2ban,
  resolveClientIp,
  syncFail2banBanEventsFromIps
} from '../../../utils/fail2ban-host'
import {
  recordSecurityInstallEventIfNeeded,
  resolveSecurityInstallStatus
} from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

export type { Fail2banBannedEntry, Fail2banJailRow } from '../../../utils/fail2ban-host'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  let settings = readFail2banSettings()
  try {
    seedFail2banSettingsIfMissing()
    settings = readFail2banSettings()
  } catch {
    /* use defaults already loaded */
  }

  try {
    const install = recordSecurityInstallEventIfNeeded('fail2ban')
    const host = await queryFail2ban('summary')

    syncFail2banBanEventsFromIps(host.bannedIps)

    return {
      ok: true,
      installed: host.installed,
      active: host.active,
      version: host.version,
      jails: host.jails,
      bannedIps: host.bannedIps,
      settings,
      clientIp: resolveClientIp(event),
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
        version: null,
        jails: [],
        bannedIps: [],
        settings,
        clientIp: null,
        installStatus: install.status,
        installMessage: install.message ?? ''
      }
    }

    const error = scriptErrorMessage(e)
    return {
      ok: false,
      error,
      installed: false,
      active: false,
      version: null,
      jails: [],
      bannedIps: [],
      settings,
      clientIp: resolveClientIp(event),
      installStatus: install.status,
      installMessage: install.message || error
    }
  }
})
