import { existsSync } from 'node:fs'
import { mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'

function stackRoot(): string {
  return process.env.STACK_ROOT || '/opt/stack'
}

export type CacheEnvelope<T = unknown> = {
  ok: boolean
  updatedAt: string
  staleAfterSec?: number
  warming?: boolean
  data?: T
}

type L1Entry = {
  mtimeMs: number
  envelope: CacheEnvelope
}

const l1 = new Map<string, L1Entry>()
const microCache = new Map<string, { at: number; value: unknown }>()

export function cacheRootDir(): string {
  return join(stackRoot(), 'data', 'panel', 'cache')
}

export function cacheFilePath(name: string): string {
  const safe = name.replace(/[^a-zA-Z0-9._/-]/g, '')
  return join(cacheRootDir(), safe)
}

export async function ensureCacheDir(): Promise<void> {
  await mkdir(cacheRootDir(), { recursive: true })
}

async function fileMtimeMs(path: string): Promise<number | null> {
  try {
    const st = await stat(path)
    return st.mtimeMs
  } catch {
    return null
  }
}

function parseEnvelope(raw: string): CacheEnvelope | null {
  try {
    return JSON.parse(raw) as CacheEnvelope
  } catch {
    return null
  }
}

export type ReadCacheResult<T = unknown> = {
  envelope: CacheEnvelope<T> | null
  ageSec: number
  isStale: boolean
  warming: boolean
  fromL1: boolean
}

export async function readCache<T = unknown>(name: string): Promise<ReadCacheResult<T>> {
  const path = cacheFilePath(name)
  const mtimeMs = await fileMtimeMs(path)

  if (mtimeMs !== null) {
    const hit = l1.get(name)
    if (hit && hit.mtimeMs === mtimeMs) {
      return envelopeResult(hit.envelope as CacheEnvelope<T>, mtimeMs, true)
    }
  }

  let raw: string
  try {
    raw = await readFile(path, 'utf8')
  } catch {
    const hit = l1.get(name)
    if (hit) {
      return envelopeResult(hit.envelope as CacheEnvelope<T>, hit.mtimeMs, true, true)
    }
    return { envelope: null, ageSec: 0, isStale: true, warming: true, fromL1: false }
  }

  let envelope = parseEnvelope(raw)
  if (!envelope && l1.has(name)) {
    const hit = l1.get(name)!
    return envelopeResult(hit.envelope as CacheEnvelope<T>, hit.mtimeMs, true, true)
  }

  if (mtimeMs !== null && envelope) {
    l1.set(name, { mtimeMs, envelope })
  }

  if (!envelope) {
    return { envelope: null, ageSec: 0, isStale: true, warming: true, fromL1: false }
  }

  return envelopeResult(envelope as CacheEnvelope<T>, mtimeMs ?? Date.now(), false)
}

function envelopeResult<T>(
  envelope: CacheEnvelope<T>,
  mtimeMs: number,
  fromL1: boolean,
  forceStale = false
): ReadCacheResult<T> {
  const updatedMs = Date.parse(envelope.updatedAt || '')
  const ageSec =
    Number.isFinite(updatedMs) && updatedMs > 0
      ? Math.max(0, Math.floor((Date.now() - updatedMs) / 1000))
      : Math.max(0, Math.floor((Date.now() - mtimeMs) / 1000))
  const staleAfter = envelope.staleAfterSec ?? 60
  const isStale = forceStale || !envelope.ok || ageSec > staleAfter
  return {
    envelope,
    ageSec,
    isStale,
    warming: !!envelope.warming,
    fromL1
  }
}

/** Collector loop only — panel must not write cache payloads in production. */
export async function writeCacheAtomic(name: string, envelope: CacheEnvelope): Promise<void> {
  await ensureCacheDir()
  const path = cacheFilePath(name)
  const tmp = `${path}.${process.pid}.${Date.now()}.tmp`
  const body = JSON.stringify(envelope, null, 2)
  await writeFile(tmp, body, 'utf8')
  await rename(tmp, path)
  l1.set(name, { mtimeMs: Date.now(), envelope })
}

export function invalidateL1(name?: string): void {
  if (name) l1.delete(name)
  else l1.clear()
}

export function readMicroCache<T>(key: string, ttlMs: number): T | undefined {
  const hit = microCache.get(key)
  if (!hit) return undefined
  if (Date.now() - hit.at > ttlMs) {
    microCache.delete(key)
    return undefined
  }
  return hit.value as T
}

export function writeMicroCache(key: string, value: unknown): void {
  microCache.set(key, { at: Date.now(), value })
}

export async function writeRegistryAtomic(path: string, data: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const tmp = `${path}.${process.pid}.${Date.now()}.tmp`
  await writeFile(tmp, `${JSON.stringify(data, null, 2)}\n`, 'utf8')
  await rename(tmp, path)
}

export async function readRegistryJson<T>(path: string): Promise<T | null> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const raw = await readFile(path, 'utf8')
      return JSON.parse(raw) as T
    } catch {
      if (attempt === 0) {
        await new Promise((r) => setTimeout(r, 15))
        continue
      }
    }
  }
  return null
}

export function panelDataDir(): string {
  return join(stackRoot(), 'data', 'panel')
}

export async function readSitesJson<T = unknown>(): Promise<T | null> {
  return readRegistryJson<T>(join(panelDataDir(), 'sites.json'))
}

export async function readDatabasesJson(): Promise<DatabaseRegistryRow[] | null> {
  const data = await readRegistryJson<DatabaseRegistryRow[]>(join(panelDataDir(), 'databases.json'))
  return Array.isArray(data) ? data : null
}

export type DatabaseRegistryRow = { name?: string; user?: string; siteDomain?: string | null }

export function mergeDatabasesList(
  cacheRows: DatabaseRegistryRow[] | undefined,
  registryRows: DatabaseRegistryRow[] | undefined
): DatabaseRegistryRow[] {
  const byName = new Map<string, DatabaseRegistryRow>()
  for (const row of registryRows || []) {
    const name = (row?.name || '').trim()
    if (name) byName.set(name, row)
  }
  for (const row of cacheRows || []) {
    const name = (row?.name || '').trim()
    if (!name) continue
    byName.set(name, { ...byName.get(name), ...row, name })
  }
  return [...byName.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([, row]) => row)
}

export function setCacheResponseHeaders(
  event: { node?: { res?: { setHeader?: (k: string, v: string) => void } } },
  result: ReadCacheResult
): void {
  const res = event.node?.res
  if (!res?.setHeader) return
  res.setHeader('X-Cache-Age', String(result.ageSec))
  res.setHeader('X-Cache-Stale', result.isStale ? '1' : '0')
  res.setHeader('X-Cache-Warming', result.warming ? '1' : '0')
}

export function cacheExists(name: string): boolean {
  return existsSync(cacheFilePath(name))
}
