import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

export type DiskProbeResponse = {
  ok: boolean
  device?: string
  devicePath?: string
  mount?: string
  rotational?: number | null
  readMbps?: number | null
  writeMbps?: number | null
  kind?: string
  probedAt?: string
  error?: string
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const raw = await runScript('host-disk-probe.sh', ['--force'], 240_000)
  return parseScriptJson<DiskProbeResponse>(raw)
})
