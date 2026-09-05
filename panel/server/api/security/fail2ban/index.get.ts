import { requireAuth } from '../../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled, readCachePayloadWithFallback } from '../../../utils/cache-read'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import {
  enrichFail2banJailsFromSettings,
  queryFail2ban,
  resolveClientIp,
  type Fail2banQueryResult
} from '../../../utils/fail2ban-host'
import { resolveSecurityInstallStatus } from '../../../utils/security-install'
import { scriptErrorMessage } from '../../../utils/stack'

export type { Fail2banBannedEntry, Fail2banJailRow } from '../../../utils/fail2ban-host'

type SecurityCachePayload = {
  fail2banSummary?: Fail2banQueryResult
}

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

  if (!cacheReadEnabled()) {
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
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityCachePayload>(
    'security.json',
    event,
    async () => ({ fail2banSummary: await queryFail2ban('summary') }),
    { sections: ['dashboard', 'settings'] }
  )
  const summary = payload?.fail2banSummary

  if (summary && typeof summary === 'object') {
    const host = enrichFail2banJailsFromSettings(summary, settings)
    return attachCacheMeta(
      {
        ok: summary.ok !== false,
        installed: host.installed,
        active: host.active,
        version: host.version,
        jails: host.jails,
        bannedIps: host.bannedIps,
        settings,
        clientIp,
        installStatus: install.status,
        installMessage: install.message ?? '',
        ...(summary.error ? { error: summary.error } : {})
      },
      result
    )
  }

  if (install.status === 'running') {
    return attachCacheMeta(
      {
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
      },
      result
    )
  }

  const error = result.warming ? 'Warming security cache…' : 'Security cache unavailable'
  return attachCacheMeta(
    {
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
    },
    result
  )
})
