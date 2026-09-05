import { requireAuth } from '../../utils/auth-guard'
import {
  readCache,
  readMicroCache,
  setCacheResponseHeaders,
  writeMicroCache
} from '../../utils/cache-store'
import { isCollectorPaused, reconcileOpRunning } from '../../utils/cache-meta'

export type DockerStatsResponse = {
  ok: boolean
  host: {
    cpuPercent: number
    memUsedBytes: number
    memTotalBytes: number
    cpuCores?: { index: number; percent: number }[]
    diskUsedBytes?: number
    diskTotalBytes?: number
    diskKind?: string
  }
  disk: {
    stackUsedBytes: number
    stackTotalBytes: number
    breakdown: { label: string; path: string; bytes: number }[]
    storage?: {
      kind: string
      device: string
      readMbps: number | null
      writeMbps: number | null
      rotational: number | null
      probedAt?: string
    }
  }
  containers: {
    name: string
    cpuPercent: number
    memUsedBytes: number
    memLimitBytes: number | null
    memPercent: number
  }[]
  _cache?: {
    ageSec: number
    stale: boolean
    warming: boolean
  }
  collectorPaused?: boolean
}

const EMPTY_STATS: DockerStatsResponse = {
  ok: false,
  host: { cpuPercent: 0, memUsedBytes: 0, memTotalBytes: 0 },
  disk: { stackUsedBytes: 0, stackTotalBytes: 0, breakdown: [] },
  containers: []
}

const STATS_FALLBACK_KEY = 'fallback:stats.json'
const STATS_FALLBACK_MS = 30_000

function withCacheMeta(
  payload: DockerStatsResponse,
  result: Awaited<ReturnType<typeof readCache>>,
  collectorPaused = false
): DockerStatsResponse {
  return {
    ...payload,
    collectorPaused,
    _cache: {
      ageSec: result.ageSec,
      stale: result.isStale,
      warming: result.warming
    }
  }
}

function freshResult(): Awaited<ReturnType<typeof readCache>> {
  return {
    envelope: null,
    ageSec: 0,
    isStale: false,
    warming: false,
    fromL1: false
  }
}

function hasUsableStats(payload: DockerStatsResponse | null | undefined): boolean {
  return Boolean(payload?.host?.memTotalBytes)
}

function normalizeStatsPayload(raw: DockerStatsResponse): DockerStatsResponse {
  return {
    ok: raw.ok !== false,
    host: raw.host,
    disk: raw.disk ?? EMPTY_STATS.disk,
    containers: raw.containers ?? []
  }
}

async function fetchStatsFromShell(): Promise<DockerStatsResponse | null> {
  const { parseScriptJson, runScript } = await import('../../utils/stack')
  const raw = await runScript('docker-stats.sh', [], 45_000)
  const parsed = parseScriptJson<DockerStatsResponse>(raw)
  return hasUsableStats(parsed) ? normalizeStatsPayload(parsed) : null
}

export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (process.env.DPANEL_CACHE_READ === '0') {
    const fresh = await fetchStatsFromShell()
    if (fresh) return fresh
    throw createError({ statusCode: 500, statusMessage: 'Could not load docker stats' })
  }

  const meta = await reconcileOpRunning()
  const collectorPaused = isCollectorPaused(meta)

  const result = await readCache<DockerStatsResponse>('stats.json')
  setCacheResponseHeaders(event, result)

  const envelope = result.envelope
  const data = envelope?.data

  if (data && typeof data === 'object' && envelope?.ok !== false) {
    const payload = normalizeStatsPayload(data as DockerStatsResponse)
    if (hasUsableStats(payload)) {
      return withCacheMeta(payload, result, collectorPaused)
    }
  }

  const cached = readMicroCache<DockerStatsResponse>(STATS_FALLBACK_KEY, STATS_FALLBACK_MS)
  if (cached && hasUsableStats(cached)) {
    return withCacheMeta(cached, freshResult(), collectorPaused)
  }

  try {
    const fresh = await fetchStatsFromShell()
    if (fresh) {
      writeMicroCache(STATS_FALLBACK_KEY, fresh)
      return withCacheMeta(fresh, freshResult(), collectorPaused)
    }
  } catch {
    /* fall through to empty */
  }

  if (data && typeof data === 'object') {
    const payload = normalizeStatsPayload(data as DockerStatsResponse)
    return withCacheMeta(payload, { ...result, warming: true, isStale: true }, collectorPaused)
  }

  return withCacheMeta(EMPTY_STATS, result, collectorPaused)
})
