import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

export type HostHardware = {
  ok?: boolean
  cpuModel?: string | null
  cpuModelFull?: string | null
  cpuThreads?: number
  memType?: string | null
  memSpeedMhz?: number | null
  diskKind?: string | null
  diskModel?: string | null
  diskDevice?: string | null
  probedAt?: string | null
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-hardware-save.sh', [], 120_000)
    const result = parseScriptJson<{ ok: boolean; hardware?: HostHardware; error?: string }>(raw)
    if (!result.ok || !result.hardware) {
      throw createError({
        statusCode: 500,
        statusMessage: result.error || 'Hardware probe failed'
      })
    }
    return { ok: true as const, hardware: result.hardware }
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'statusCode' in e) throw e
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Hardware refresh failed'
    })
  }
})
