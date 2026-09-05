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

/** Global kill switch — disables dashboard cache reads when `DPANEL_CACHE_READ=0`. */
export function cacheReadEnabled(): boolean {
  return process.env.DPANEL_CACHE_READ !== '0'
}

/** Cache is only for dashboard polling (stats + security summary). Business GETs use live data. */
export function dashboardCacheReadEnabled(): boolean {
  return cacheReadEnabled()
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

function isPayloadComplete(
  payload: unknown,
  isPayloadUsable?: (payload: unknown) => boolean
): boolean {
  if (isPayloadUsable) return isPayloadUsable(payload)
  return !!payload
}

function needsStaleFallback(
  payload: unknown,
  result: ReadCacheResult,
  isPayloadUsable?: (payload: unknown) => boolean
): boolean {
  if (!isPayloadComplete(payload, isPayloadUsable)) return true
  if (result.warming) return true
  if (result.isStale && result.ageSec >= staleFallbackSec()) return true
  return false
}

function isColdCacheMiss(
  payload: unknown,
  result: ReadCacheResult,
  isPayloadUsable?: (payload: unknown) => boolean
): boolean {
  return !isPayloadComplete(payload, isPayloadUsable) || result.warming
}

export function freshFallbackResult(): ReadCacheResult {
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
  opts?: {
    sections?: CacheSectionKey[]
    isPayloadUsable?: (payload: T | null) => boolean
  }
): Promise<{ payload: T | null; result: ReadCacheResult; fromFallback: boolean }> {
  const isPayloadUsable = opts?.isPayloadUsable as ((payload: unknown) => boolean) | undefined
  const { payload, result } = await readCachePayload<T>(name, event)

  if (!needsStaleFallback(payload, result, isPayloadUsable)) {
    return { payload, result, fromFallback: false }
  }

  const coldMiss = isColdCacheMiss(payload, result, isPayloadUsable)
  const sections = opts?.sections
  if (!coldMiss && sections?.length) {
    const meta = await readCacheMeta()
    if (!isAnySectionActive(meta, sections)) {
      return { payload, result, fromFallback: false }
    }
  }

  const microKey = `fallback:${name}:${sections?.join(',') || 'any'}`
  const cached = readMicroCache<T>(microKey, FALLBACK_DEBOUNCE_MS)
  if (cached && isPayloadComplete(cached, isPayloadUsable)) {
    return { payload: cached, result: freshFallbackResult(), fromFallback: true }
  }

  try {
    const fresh = await fallback()
    if (fresh && isPayloadComplete(fresh, isPayloadUsable)) {
      writeMicroCache(microKey, fresh)
      return { payload: fresh, result: freshFallbackResult(), fromFallback: true }
    }
  } catch {
    /* keep cache / empty result */
  }

  return { payload, result, fromFallback: false }
}
