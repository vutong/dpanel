import type { H3Event } from 'h3'
import {
  filterBannedIps,
  getGeoipStatus,
  isValidBanIp,
  lookupIpGeoBatch,
  type IpGeoEntry
} from './geoip'
import {
  readFail2banKnownIps,
  syncFail2banBanEvents,
  writeFail2banKnownIps
} from './security-events'
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
  return (
    String(getHeader(event, 'x-forwarded-for') || '')
      .split(',')[0]
      ?.trim() ||
    getRequestIP(event, { xForwardedFor: true }) ||
    null
  )
}

export async function queryFail2ban(mode: Fail2banQueryMode): Promise<Fail2banQueryResult> {
  const raw = await runScript('host-fail2ban-query.sh', [mode], 90_000)
  return sanitizeQueryResult(parseScriptJson<Fail2banQueryResult>(raw))
}

export function sanitizeQueryResult(result: Fail2banQueryResult): Fail2banQueryResult {
  result.bannedIps = filterBannedIps(result.bannedIps || [])
  result.jails = (result.jails || []).map((jail) => ({
    ...jail,
    bannedIps: (jail.bannedIps || []).filter((entry) => isValidBanIp(entry.ip))
  }))
  return result
}

export function collectBannedIps(jails: Fail2banJailRow[], bannedIps: string[]): string[] {
  const set = new Set<string>(filterBannedIps(bannedIps || []))
  for (const jail of jails || []) {
    for (const entry of jail.bannedIps || []) {
      if (isValidBanIp(entry.ip)) set.add(entry.ip)
    }
  }
  return [...set]
}

export function syncFail2banBanEventsFromIps(bannedIps: string[]): void {
  const ips = filterBannedIps(bannedIps || [])
  if (!ips.length) return
  const known = readFail2banKnownIps()
  syncFail2banBanEvents(ips, known)
  writeFail2banKnownIps(known)
}

export function buildIpGeoMap(jails: Fail2banJailRow[], bannedIps: string[]): Record<string, IpGeoEntry> {
  return lookupIpGeoBatch(collectBannedIps(jails, bannedIps))
}

export function buildGeoipStatusPayload() {
  const geoStatus = getGeoipStatus()
  return {
    ready: geoStatus.ready,
    syncedAt: geoStatus.meta?.syncedAt ?? null,
    buildDate: geoStatus.meta?.buildDate ?? null,
    edition: geoStatus.meta?.edition ?? null,
    filename: geoStatus.meta?.filename ?? null
  }
}
