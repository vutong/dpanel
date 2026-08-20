import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync
} from 'node:fs'
import { dirname, join } from 'node:path'
import { isValidBanIp } from './fail2ban-ip'
import { stackRoot } from './stack'

const PROVIDER = 'country.is' as const
const COUNTRY_IS_BASE = 'https://api.country.is'
const LOOKUP_CONCURRENCY = 4

export type IpGeoEntry = {
  countryCode: string | null
  countryName: string | null
  flag: string
}

export type GeoBlocklistEntry = {
  countryCode: string | null
  countryName: string | null
  syncedAt: string
}

export type GeoBlocklist = {
  provider: typeof PROVIDER
  updatedAt: string
  entries: Record<string, GeoBlocklistEntry>
}

export type GeoipSyncResult = {
  provider: typeof PROVIDER
  syncedAt: string
  total: number
  resolved: number
  missing: number
}

type CountryIsResponse = {
  ip?: string
  country?: string
  error?: string
}

let regionNames: Intl.DisplayNames | null = null

export function geoBlocklistPath(): string {
  return join(stackRoot(), 'data', 'panel', 'geo-blocklist.json')
}

function ensurePanelDataDir(): void {
  const dir = dirname(geoBlocklistPath())
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true })
  }
}

function defaultBlocklist(): GeoBlocklist {
  return {
    provider: PROVIDER,
    updatedAt: new Date(0).toISOString(),
    entries: {}
  }
}

export function readGeoBlocklist(): GeoBlocklist {
  const path = geoBlocklistPath()
  if (!existsSync(path)) return defaultBlocklist()
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf8')) as Partial<GeoBlocklist>
    const entries =
      parsed.entries && typeof parsed.entries === 'object' && !Array.isArray(parsed.entries)
        ? (parsed.entries as Record<string, GeoBlocklistEntry>)
        : {}
    return {
      provider: PROVIDER,
      updatedAt: typeof parsed.updatedAt === 'string' ? parsed.updatedAt : new Date(0).toISOString(),
      entries
    }
  } catch {
    return defaultBlocklist()
  }
}

export function writeGeoBlocklist(db: GeoBlocklist): void {
  ensurePanelDataDir()
  writeFileSync(geoBlocklistPath(), `${JSON.stringify(db, null, 2)}\n`, 'utf8')
}

export function isGeoipReady(): boolean {
  return existsSync(geoBlocklistPath())
}

export function countryFlag(code: string | null | undefined): string {
  if (!code || code.length !== 2) return ''
  const upper = code.toUpperCase()
  if (!/^[A-Z]{2}$/.test(upper)) return ''
  return String.fromCodePoint(
    ...[...upper].map((char) => 0x1f1e6 - 65 + char.charCodeAt(0))
  )
}

function countryNameFromCode(code: string | null): string | null {
  if (!code || code.length !== 2) return null
  const upper = code.toUpperCase()
  try {
    if (!regionNames) {
      regionNames = new Intl.DisplayNames(['en'], { type: 'region' })
    }
    return regionNames.of(upper) ?? null
  } catch {
    return null
  }
}

function toIpGeoEntry(entry: {
  countryCode: string | null
  countryName: string | null
}): IpGeoEntry {
  return {
    countryCode: entry.countryCode,
    countryName: entry.countryName,
    flag: countryFlag(entry.countryCode)
  }
}

function emptyIpGeo(): IpGeoEntry {
  return { countryCode: null, countryName: null, flag: '' }
}

async function fetchCountryIs(ip: string): Promise<{
  countryCode: string | null
  countryName: string | null
} | null> {
  try {
    const res = await fetch(`${COUNTRY_IS_BASE}/${encodeURIComponent(ip)}`, {
      headers: { Accept: 'application/json' }
    })
    if (!res.ok) {
      // 404 / private ranges: treat as resolved-null so we do not retry forever
      if (res.status === 404 || res.status === 400) {
        return { countryCode: null, countryName: null }
      }
      return null
    }
    const body = (await res.json()) as CountryIsResponse
    if (body.error) {
      return { countryCode: null, countryName: null }
    }
    const countryCode = body.country?.trim().toUpperCase() || null
    if (!countryCode || !/^[A-Z]{2}$/.test(countryCode)) {
      return { countryCode: null, countryName: null }
    }
    return {
      countryCode,
      countryName: countryNameFromCode(countryCode)
    }
  } catch {
    return null
  }
}

async function mapPool<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const results: R[] = new Array(items.length)
  let next = 0

  async function worker() {
    while (next < items.length) {
      const i = next++
      results[i] = await fn(items[i])
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, items.length) }, () => worker())
  await Promise.all(workers)
  return results
}

/**
 * Resolve country for IPs from geo-blocklist.json.
 * Option B: missing IPs are looked up via country.is and persisted.
 */
export async function lookupIpGeoBatch(
  ips: string[],
  options?: { force?: boolean }
): Promise<Record<string, IpGeoEntry>> {
  const unique = [...new Set(ips.filter(isValidBanIp))]
  if (!unique.length) return {}

  const force = options?.force === true
  const db = readGeoBlocklist()
  const out: Record<string, IpGeoEntry> = {}
  const missing: string[] = []

  for (const ip of unique) {
    const existing = db.entries[ip]
    if (!force && existing) {
      out[ip] = toIpGeoEntry(existing)
      continue
    }
    missing.push(ip)
  }

  if (!missing.length) return out

  const syncedAt = new Date().toISOString()
  let dirty = false

  await mapPool(missing, LOOKUP_CONCURRENCY, async (ip) => {
    const resolved = await fetchCountryIs(ip)
    if (!resolved) {
      out[ip] = emptyIpGeo()
      return
    }
    db.entries[ip] = {
      countryCode: resolved.countryCode,
      countryName: resolved.countryName,
      syncedAt
    }
    out[ip] = toIpGeoEntry(resolved)
    dirty = true
  })

  if (dirty) {
    db.updatedAt = syncedAt
    writeGeoBlocklist(db)
  }

  return out
}

export async function lookupIpGeo(ip: string): Promise<IpGeoEntry> {
  if (!isValidBanIp(ip)) return emptyIpGeo()
  const map = await lookupIpGeoBatch([ip])
  return map[ip] ?? emptyIpGeo()
}

/** Force-refresh country data for the given IPs into geo-blocklist.json. */
export async function syncGeoipDatabase(ips: string[]): Promise<GeoipSyncResult> {
  const unique = [...new Set(ips.filter(isValidBanIp))]
  const syncedAt = new Date().toISOString()

  if (!unique.length) {
    const db = readGeoBlocklist()
    writeGeoBlocklist({ ...db, updatedAt: syncedAt })
    return {
      provider: PROVIDER,
      syncedAt,
      total: 0,
      resolved: 0,
      missing: 0
    }
  }

  const map = await lookupIpGeoBatch(unique, { force: true })
  let resolved = 0
  let missing = 0
  for (const ip of unique) {
    const entry = map[ip]
    if (entry?.countryCode) resolved++
    else missing++
  }

  // Ensure Sync always bumps updatedAt even if every lookup failed (network down)
  const db = readGeoBlocklist()
  if (db.updatedAt !== syncedAt) {
    db.updatedAt = syncedAt
    writeGeoBlocklist(db)
  }

  return {
    provider: PROVIDER,
    syncedAt,
    total: unique.length,
    resolved,
    missing
  }
}

export function getGeoipStatus(): {
  ready: boolean
  syncedAt: string | null
  provider: typeof PROVIDER
  count: number
} {
  const db = readGeoBlocklist()
  const count = Object.keys(db.entries).length
  const ready = isGeoipReady() || count > 0
  const syncedAt =
    ready && db.updatedAt && db.updatedAt !== new Date(0).toISOString()
      ? db.updatedAt
      : null
  return {
    ready,
    syncedAt,
    provider: PROVIDER,
    count
  }
}
