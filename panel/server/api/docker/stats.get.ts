import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../utils/stack'

export type DockerStatsResponse = {
  ok: boolean
  host: {
    cpuPercent: number
    memUsedBytes: number
    memTotalBytes: number
  }
  disk: {
    stackUsedBytes: number
    stackTotalBytes: number
    breakdown: { label: string; path: string; bytes: number }[]
  }
  containers: {
    name: string
    cpuPercent: number
    memUsedBytes: number
    memLimitBytes: number | null
    memPercent: number
  }[]
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const raw = await runScript('docker-stats.sh', [], 45_000)
  return parseScriptJson<DockerStatsResponse>(raw)
})
