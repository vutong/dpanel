import { requireAuth } from '../../utils/auth-guard'
import { readCache, setCacheResponseHeaders } from '../../utils/cache-store'
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

export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (process.env.DPANEL_CACHE_READ === '0') {
    const { parseScriptJson, runScript } = await import('../../utils/stack')
    const raw = await runScript('docker-stats.sh', [], 45_000)
    return parseScriptJson<DockerStatsResponse>(raw)
  }

  const meta = await reconcileOpRunning()
  const collectorPaused = isCollectorPaused(meta)

  const result = await readCache<DockerStatsResponse>('stats.json')
  setCacheResponseHeaders(event, result)

  const envelope = result.envelope
  const data = envelope?.data

  if (data && typeof data === 'object' && envelope?.ok !== false) {
    const payload = data as DockerStatsResponse
    return withCacheMeta(
      {
        ok: payload.ok !== false,
        host: payload.host,
        disk: payload.disk,
        containers: payload.containers ?? []
      },
      result,
      collectorPaused
    )
  }

  if (data && typeof data === 'object') {
    const payload = data as DockerStatsResponse
    return withCacheMeta(
      {
        ok: payload.ok !== false,
        host: payload.host ?? EMPTY_STATS.host,
        disk: payload.disk ?? EMPTY_STATS.disk,
        containers: payload.containers ?? []
      },
      { ...result, warming: true, isStale: true },
      collectorPaused
    )
  }

  return withCacheMeta(EMPTY_STATS, result, collectorPaused)
})
