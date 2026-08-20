import { execFile } from 'node:child_process'
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync
} from 'node:fs'
import { join } from 'node:path'
import { promisify } from 'node:util'
import { open } from 'mmdb-lib'
import { stackRoot } from './stack'

const execFileAsync = promisify(execFile)

/** Known MaxMind GeoLite2 editions the panel may sync and query. */
export const MAXMIND_DATABASES = {
  country: {
    edition: 'GeoLite2-Country',
    filename: 'GeoLite2-Country.mmdb'
  }
} as const

export type MaxMindEditionId = (typeof MAXMIND_DATABASES)[keyof typeof MAXMIND_DATABASES]['edition']

export type MaxMindDatabaseEntry = {
  edition: string
  filename: string
  syncedAt: string
  buildDate?: string | null
}

export type MaxMindState = {
  provider: 'maxmind'
  updatedAt: string
  databases: Record<string, MaxMindDatabaseEntry>
}

/** @deprecated Use MaxMindDatabaseEntry via getMaxMindCountryEntry() */
export type GeoipMeta = MaxMindDatabaseEntry

export type IpGeoEntry = {
  countryCode: string | null
  countryName: string | null
  flag: string
}

type LookupCache = Record<string, { countryCode: string | null; countryName: string | null }>

type MmdbCountryRecord = {
  country?: {
    iso_code?: string
    names?: Record<string, string>
  }
  registered_country?: {
    iso_code?: string
    names?: Record<string, string>
  }
}

const COUNTRY_EDITION = MAXMIND_DATABASES.country.edition

export function geoipDir(): string {
  return join(stackRoot(), 'data', 'panel', 'geoip')
}

export function maxmindPath(): string {
  return join(geoipDir(), 'maxmind.json')
}

/** @deprecated Use maxmindPath() */
export function geoipMetaPath(): string {
  return maxmindPath()
}

export function maxmindMmdbPath(edition: MaxMindEditionId = COUNTRY_EDITION): string {
  const entry = getMaxMindDatabaseEntry(edition)
  const filename = entry?.filename ?? editionToFilename(edition)
  return join(geoipDir(), filename)
}

/** @deprecated Use maxmindMmdbPath() */
export function geoipMmdbPath(): string {
  return maxmindMmdbPath(COUNTRY_EDITION)
}

export function geoipCachePath(): string {
  return join(geoipDir(), 'lookup-cache.json')
}

function editionToFilename(edition: string): string {
  return `${edition}.mmdb`
}

function defaultMaxMindState(): MaxMindState {
  return {
    provider: 'maxmind',
    updatedAt: new Date(0).toISOString(),
    databases: {}
  }
}

function migrateLegacyMetaJson(): MaxMindState | null {
  const legacyPath = join(geoipDir(), 'meta.json')
  if (!existsSync(legacyPath)) return null
  try {
    const legacy = JSON.parse(readFileSync(legacyPath, 'utf8')) as {
      edition?: string
      syncedAt?: string
      buildDate?: string | null
    }
    if (!legacy.edition || !legacy.syncedAt) return null
    const state = defaultMaxMindState()
    state.databases[legacy.edition] = {
      edition: legacy.edition,
      filename: editionToFilename(legacy.edition),
      syncedAt: legacy.syncedAt,
      buildDate: legacy.buildDate ?? null
    }
    state.updatedAt = legacy.syncedAt
    writeMaxMindState(state)
    rmSync(legacyPath, { force: true })
    return state
  } catch {
    return null
  }
}

export function readMaxMindState(): MaxMindState {
  const path = maxmindPath()
  if (!existsSync(path)) {
    const migrated = migrateLegacyMetaJson()
    if (migrated) return migrated
    return defaultMaxMindState()
  }
  try {
    const parsed = JSON.parse(readFileSync(path, 'utf8')) as Partial<MaxMindState>
    return {
      provider: 'maxmind',
      updatedAt: parsed.updatedAt || new Date(0).toISOString(),
      databases: parsed.databases && typeof parsed.databases === 'object' ? parsed.databases : {}
    }
  } catch {
    return defaultMaxMindState()
  }
}

export function writeMaxMindState(state: MaxMindState): void {
  ensureGeoipDir()
  writeFileSync(maxmindPath(), `${JSON.stringify(state, null, 2)}\n`, 'utf8')
}

export function getMaxMindDatabaseEntry(edition: string): MaxMindDatabaseEntry | null {
  return readMaxMindState().databases[edition] ?? null
}

export function getMaxMindCountryEntry(): MaxMindDatabaseEntry | null {
  return getMaxMindDatabaseEntry(COUNTRY_EDITION)
}

/** @deprecated Use readMaxMindState() / getMaxMindCountryEntry() */
export function readGeoipMeta(): MaxMindDatabaseEntry | null {
  return getMaxMindCountryEntry()
}

export function isMaxMindDatabaseReady(edition: MaxMindEditionId = COUNTRY_EDITION): boolean {
  const path = maxmindMmdbPath(edition)
  return existsSync(path) && statSync(path).size > 0
}

export function isGeoipReady(): boolean {
  return isMaxMindDatabaseReady(COUNTRY_EDITION)
}

export function isValidBanIp(ip: string): boolean {
  const s = ip.trim()
  if (!s || !/^[0-9a-fA-F:.]+$/.test(s)) return false
  if (/^\d+$/.test(s)) return false
  if (!s.includes('.') && !s.includes(':')) return false
  return true
}

export function filterBannedIps(ips: string[]): string[] {
  return ips.filter(isValidBanIp)
}

function ensureGeoipDir(): void {
  const dir = geoipDir()
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true })
  }
}

function readLookupCache(): LookupCache {
  const path = geoipCachePath()
  if (!existsSync(path)) return {}
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as LookupCache
  } catch {
    return {}
  }
}

function writeLookupCache(cache: LookupCache): void {
  ensureGeoipDir()
  writeFileSync(geoipCachePath(), `${JSON.stringify(cache, null, 2)}\n`, 'utf8')
}

export function countryFlag(code: string | null | undefined): string {
  if (!code || code.length !== 2) return ''
  const upper = code.toUpperCase()
  if (!/^[A-Z]{2}$/.test(upper)) return ''
  return String.fromCodePoint(
    ...[...upper].map((char) => 0x1f1e6 - 65 + char.charCodeAt(0))
  )
}

function lookupFromMmdb(ip: string, db?: ReturnType<typeof open> | null): {
  countryCode: string | null
  countryName: string | null
} {
  let reader = db
  let closeAfter = false
  if (!reader) {
    const path = maxmindMmdbPath(COUNTRY_EDITION)
    if (!existsSync(path)) {
      return { countryCode: null, countryName: null }
    }
    try {
      reader = open(readFileSync(path))
      closeAfter = true
    } catch {
      return { countryCode: null, countryName: null }
    }
  }

  try {
    const record = reader.get(ip) as MmdbCountryRecord | null
    const country = record?.country ?? record?.registered_country
    const countryCode = country?.iso_code?.toUpperCase() ?? null
    const countryName = country?.names?.en ?? null
    return { countryCode, countryName }
  } catch {
    return { countryCode: null, countryName: null }
  } finally {
    if (closeAfter) {
      reader.close?.()
    }
  }
}

function toIpGeoEntry(entry: { countryCode: string | null; countryName: string | null }): IpGeoEntry {
  return {
    countryCode: entry.countryCode,
    countryName: entry.countryName,
    flag: countryFlag(entry.countryCode)
  }
}

export function lookupIpGeo(ip: string): IpGeoEntry {
  if (!isValidBanIp(ip)) {
    return { countryCode: null, countryName: null, flag: '' }
  }

  const cache = readLookupCache()
  const cached = cache[ip]
  if (cached) {
    return toIpGeoEntry(cached)
  }

  const resolved = isGeoipReady() ? lookupFromMmdb(ip) : { countryCode: null, countryName: null }
  cache[ip] = resolved
  writeLookupCache(cache)
  return toIpGeoEntry(resolved)
}

export function lookupIpGeoBatch(ips: string[]): Record<string, IpGeoEntry> {
  const unique = [...new Set(ips.filter(isValidBanIp))]
  if (!unique.length) return {}

  const cache = readLookupCache()
  const out: Record<string, IpGeoEntry> = {}
  let cacheDirty = false

  let reader: ReturnType<typeof open> | null = null
  if (isGeoipReady()) {
    try {
      reader = open(readFileSync(maxmindMmdbPath(COUNTRY_EDITION)))
    } catch {
      reader = null
    }
  }

  try {
    for (const ip of unique) {
      const cached = cache[ip]
      if (cached) {
        out[ip] = toIpGeoEntry(cached)
        continue
      }

      const resolved = reader
        ? lookupFromMmdb(ip, reader)
        : { countryCode: null, countryName: null }
      cache[ip] = resolved
      out[ip] = toIpGeoEntry(resolved)
      cacheDirty = true
    }
  } finally {
    reader?.close?.()
  }

  if (cacheDirty) {
    writeLookupCache(cache)
  }

  return out
}

function findMmdbFile(dir: string, filename: string): string | null {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name)
    const st = statSync(path)
    if (st.isDirectory()) {
      const nested = findMmdbFile(path, filename)
      if (nested) return nested
      continue
    }
    if (name === filename) return path
  }
  return null
}

function upsertMaxMindDatabaseEntry(
  edition: string,
  filename: string,
  buildDate: string | null
): MaxMindDatabaseEntry {
  const syncedAt = new Date().toISOString()
  const entry: MaxMindDatabaseEntry = {
    edition,
    filename,
    syncedAt,
    buildDate
  }

  const state = readMaxMindState()
  state.databases[edition] = entry
  state.updatedAt = syncedAt
  writeMaxMindState(state)
  return entry
}

export async function syncMaxMindDatabase(
  edition: MaxMindEditionId = COUNTRY_EDITION
): Promise<MaxMindDatabaseEntry> {
  const licenseKey = String(process.env.GEOIP_MAXMIND_LICENSE_KEY || '').trim()
  if (!licenseKey) {
    throw new Error(
      'Set GEOIP_MAXMIND_LICENSE_KEY in /opt/stack/.env (free MaxMind GeoLite2 license key)'
    )
  }

  const filename = editionToFilename(edition)

  ensureGeoipDir()
  const dir = geoipDir()
  const tarPath = join(dir, `${edition}.download.tar.gz`)
  const extractDir = join(dir, `.extract-${edition}`)
  const mmdbPath = join(dir, filename)

  rmSync(extractDir, { recursive: true, force: true })
  mkdirSync(extractDir, { recursive: true })

  const url =
    `https://download.maxmind.com/app/geoip_download?edition_id=${edition}` +
    `&license_key=${encodeURIComponent(licenseKey)}&suffix=tar.gz`

  const res = await fetch(url, { redirect: 'follow' })
  if (!res.ok) {
    throw new Error(`MaxMind download failed (HTTP ${res.status})`)
  }

  const buf = Buffer.from(await res.arrayBuffer())
  if (buf.length < 512) {
    const text = buf.toString('utf8')
    if (text.includes('error') || text.includes('Invalid')) {
      throw new Error(`MaxMind download error: ${text.slice(0, 200)}`)
    }
  }

  writeFileSync(tarPath, buf)
  await execFileAsync('tar', ['-xzf', tarPath, '-C', extractDir])

  const found = findMmdbFile(extractDir, filename)
  if (!found) {
    throw new Error(`${filename} not found in downloaded archive`)
  }

  let buildDate: string | null = null
  const buildMatch = found.match(new RegExp(`${edition}_(\\d{8})`))
  if (buildMatch) {
    buildDate = buildMatch[1]
  }

  const tmpMmdb = join(dir, `${filename}.tmp`)
  renameSync(found, tmpMmdb)
  renameSync(tmpMmdb, mmdbPath)

  const entry = upsertMaxMindDatabaseEntry(edition, filename, buildDate)

  rmSync(extractDir, { recursive: true, force: true })
  rmSync(tarPath, { force: true })

  return entry
}

/** Sync GeoLite2-Country (Fail2ban country column). */
export async function syncGeoipDatabase(): Promise<MaxMindDatabaseEntry> {
  return syncMaxMindDatabase(COUNTRY_EDITION)
}

export function getMaxMindStatus(edition: MaxMindEditionId = COUNTRY_EDITION): {
  ready: boolean
  entry: MaxMindDatabaseEntry | null
  state: MaxMindState
} {
  return {
    ready: isMaxMindDatabaseReady(edition),
    entry: getMaxMindDatabaseEntry(edition),
    state: readMaxMindState()
  }
}

export function getGeoipStatus(): {
  ready: boolean
  meta: MaxMindDatabaseEntry | null
  maxmind: MaxMindState
} {
  const status = getMaxMindStatus(COUNTRY_EDITION)
  return {
    ready: status.ready,
    meta: status.entry,
    maxmind: status.state
  }
}
