import type { H3Event } from 'h3'
import type { CacheSectionKey } from './cache-meta'
import { isAnySectionActive, readCacheMeta } from './cache-meta'
import {
  readCache,
  readMicroCache,
  setCacheResponseHeaders,
  writeMicroCache,
  type ReadCacheResult
} from './cache-store'

export type CacheMetaFields = {
  ageSec: number
  stale: boolean
  warming: boolean
}

const FALLBACK_DEBOUNCE_MS = 30_000

export function cacheReadEnabled(): boolean {
  return process.env.DPANEL_CACHE_READ !== '0'
}

export function staleFallbackSec(): number {
  return Number(process.env.DPANEL_CACHE_STALE_FALLBACK_SEC || 180)
}

export function attachCacheMeta<T extends Record<string, unknown>>(
  payload: T,
  result: ReadCacheResult
): T & { _cache: CacheMetaFields } {
  return {
    ...payload,
    _cache: {
      ageSec: result.ageSec,
      stale: result.isStale,
      warming: result.warming
    }
  }
}

export async function readCachePayload<T extends Record<string, unknown>>(
  name: string,
  event?: H3Event
): Promise<{ payload: T | null; result: ReadCacheResult }> {
  const result = await readCache<T>(name)
  if (event) setCacheResponseHeaders(event, result)
  const data = result.envelope?.data
  const payload =
    data && typeof data === 'object' && !Array.isArray(data) ? (data as T) : null
  return { payload, result }
}

function needsStaleFallback(payload: unknown, result: ReadCacheResult): boolean {
  if (!payload) return true
  if (result.warming) return true
  if (result.isStale && result.ageSec >= staleFallbackSec()) return true
  return false
}

function isColdCacheMiss(payload: unknown, result: ReadCacheResult): boolean {
  return !payload || result.warming
}

function freshFallbackResult(): ReadCacheResult {
  return {
    envelope: null,
    ageSec: 0,
    isStale: false,
    warming: false,
    fromL1: false
  }
}

/** Read cache file; optionally run shell fallback once when stale/missing and section is active. */
export async function readCachePayloadWithFallback<T extends Record<string, unknown>>(
  name: string,
  event: H3Event | undefined,
  fallback: () => Promise<T | null>,
  opts?: { sections?: CacheSectionKey[] }
): Promise<{ payload: T | null; result: ReadCacheResult; fromFallback: boolean }> {
  const { payload, result } = await readCachePayload<T>(name, event)

  if (!needsStaleFallback(payload, result)) {
    return { payload, result, fromFallback: false }
  }

  const coldMiss = isColdCacheMiss(payload, result)
  const sections = opts?.sections
  if (!coldMiss && sections?.length) {
    const meta = await readCacheMeta()
    if (!isAnySectionActive(meta, sections)) {
      return { payload, result, fromFallback: false }
    }
  }

  const microKey = `fallback:${name}:${sections?.join(',') || 'any'}`
  const cached = readMicroCache<T>(microKey, FALLBACK_DEBOUNCE_MS)
  if (cached) {
    return { payload: cached, result: freshFallbackResult(), fromFallback: true }
  }

  try {
    const fresh = await fallback()
    if (fresh) {
      writeMicroCache(microKey, fresh)
      return { payload: fresh, result: freshFallbackResult(), fromFallback: true }
    }
  } catch {
    /* keep cache / empty result */
  }

  return { payload, result, fromFallback: false }
}
