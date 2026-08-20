import { getHeader, getRequestIP, type H3Event } from 'h3'
import {
  readFail2banKnownIps,
  syncFail2banBanEvents,
  writeFail2banKnownIps
} from './security-events'
import { filterBannedIps, isValidBanIp } from './fail2ban-ip'
import { parseScriptJson, runScript } from './stack'

export type Fail2banQueryMode = 'summary' | 'jails' | 'banned'

export type Fail2banBannedEntry = {
  ip: string
  bannedAt: string | null
}

export type Fail2banJailRow = {
  name: string
  managedBy?: 'dpanel' | 'system'
  enabled?: boolean
  filter?: string | null
  logpath?: string | null
  maxretry?: number
  findtime?: number
  bantime?: number
  currentlyFailed?: number
  totalFailed?: number
  totalBanned?: number
  bannedIps?: Fail2banBannedEntry[]
}

export type Fail2banQueryResult = {
  ok: boolean
  mode?: string
  installed: boolean
  active: boolean
  version: string | null
  global?: { ignoreip: string[] }
  jails: Fail2banJailRow[]
  bannedIps: string[]
  error?: string
}

export function resolveClientIp(event: H3Event): string | null {
  try {
    return (
      String(getHeader(event, 'x-forwarded-for') || '')
        .split(',')[0]
        ?.trim() ||
      getRequestIP(event, { xForwardedFor: true }) ||
      null
    )
  } catch {
    return null
  }
}

export async function queryFail2ban(mode: Fail2banQueryMode): Promise<Fail2banQueryResult> {
  const raw = await runScript('host-fail2ban-query.sh', [mode], 90_000)
  const parsed = parseScriptJson<Fail2banQueryResult>(raw)
  if (parsed.ok === false && parsed.error) {
    throw new Error(String(parsed.error))
  }
  return sanitizeQueryResult(parsed)
}

function normalizeBannedEntry(entry: unknown): Fail2banBannedEntry | null {
  if (typeof entry === 'string') {
    return isValidBanIp(entry) ? { ip: entry, bannedAt: null } : null
  }
  if (entry && typeof entry === 'object' && 'ip' in entry) {
    const ip = String((entry as Fail2banBannedEntry).ip || '')
    if (!isValidBanIp(ip)) return null
    return {
      ip,
      bannedAt: (entry as Fail2banBannedEntry).bannedAt ?? null
    }
  }
  return null
}

export function sanitizeQueryResult(result: Fail2banQueryResult): Fail2banQueryResult {
  result.bannedIps = filterBannedIps(result.bannedIps || [])
  result.jails = (result.jails || []).map((jail) => ({
    ...jail,
    bannedIps: (jail.bannedIps || [])
      .map(normalizeBannedEntry)
      .filter((entry): entry is Fail2banBannedEntry => entry !== null)
  }))
  return result
}

export function syncFail2banBanEventsFromIps(bannedIps: string[]): void {
  const ips = filterBannedIps(bannedIps || [])
  if (!ips.length) return
  const known = readFail2banKnownIps()
  syncFail2banBanEvents(ips, known)
  writeFail2banKnownIps(known)
}

export { filterBannedIps, isValidBanIp }
