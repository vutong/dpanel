import { requireAuth } from '../../../utils/auth-guard'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import {
  enrichFail2banJailsFromSettings,
  queryFail2ban,
  resolveClientIp
} from '../../../utils/fail2ban-host'
import { resolveSecurityInstallStatus } from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

export type { Fail2banBannedEntry, Fail2banJailRow } from '../../../utils/fail2ban-host'

/** Live Fail2ban summary — no cache (settings / ops). */
export default defineEventHandler(async (event) => {
  requireAuth(event)

  let settings = readFail2banSettings()
  try {
    seedFail2banSettingsIfMissing()
    settings = readFail2banSettings()
  } catch {
    /* use defaults already loaded */
  }

  const install = resolveSecurityInstallStatus('fail2ban')
  const clientIp = resolveClientIp(event)

  try {
    const host = enrichFail2banJailsFromSettings(await queryFail2ban('summary'), settings)
    return {
      ok: true,
      installed: host.installed,
      active: host.active,
      version: host.version,
      jails: host.jails,
      bannedIps: host.bannedIps,
      settings,
      clientIp,
      installStatus: install.status,
      installMessage: install.message ?? ''
    }
  } catch (e: unknown) {
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
      active: false,
      version: null,
      jails: [],
      bannedIps: [],
      settings,
      clientIp,
      installStatus: install.status,
      installMessage: install.message || error
    }
  }
})
