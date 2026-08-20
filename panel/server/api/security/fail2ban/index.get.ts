import { requireAuth } from '../../../utils/auth-guard'
import { readFail2banSettings, seedFail2banSettingsIfMissing } from '../../../utils/fail2ban-settings'
import { fetchHostSecurityStatus } from '../../../utils/host-security'
import {
  recordSecurityInstallEventIfNeeded,
  resolveSecurityInstallStatus
} from '../../../utils/security-install'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export type Fail2banBannedEntry = {
  ip: string
  bannedAt: string | null
}

export type Fail2banJailDetail = {
  name: string
  managedBy: 'dpanel' | 'system'
  enabled: boolean
  filter: string | null
  logpath: string | null
  maxretry: number
  findtime: number
  bantime: number
  currentlyFailed: number
  totalFailed: number
  totalBanned: number
  bannedIps: Fail2banBannedEntry[]
}

export type Fail2banDetail = {
  ok: boolean
  installed: boolean
  active: boolean
  version: string | null
  global: { ignoreip: string[] }
  jails: Fail2banJailDetail[]
  bannedIps: string[]
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  seedFail2banSettingsIfMissing()
  const settings = readFail2banSettings()

  try {
    const install = recordSecurityInstallEventIfNeeded('fail2ban')
    const status = await fetchHostSecurityStatus()

    let detail: Fail2banDetail | null = null
    if (status.fail2ban?.installed) {
      try {
        const raw = await runScript('host-fail2ban-detail.sh', [], 120_000)
        detail = parseScriptJson<Fail2banDetail>(raw)
      } catch {
        detail = null
      }
    }

    const clientIp =
      String(getHeader(event, 'x-forwarded-for') || '')
        .split(',')[0]
        ?.trim() ||
      getRequestIP(event, { xForwardedFor: true }) ||
      null

    return {
      ok: true,
      installed: status.fail2ban?.installed ?? false,
      active: status.fail2ban?.active ?? false,
      jails: detail?.jails ?? status.fail2ban?.jails ?? [],
      bannedIps: detail?.bannedIps ?? status.fail2ban?.bannedIps ?? [],
      version: detail?.version ?? null,
      global: detail?.global ?? { ignoreip: settings.ignoreip },
      settings,
      clientIp,
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
        version: null,
        global: { ignoreip: settings.ignoreip },
        settings,
        clientIp: null,
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
