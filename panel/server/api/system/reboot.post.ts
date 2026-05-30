import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const raw = await runScript('vps-reboot.sh', [], 15_000)
  return parseScriptJson<{ ok: boolean; message?: string }>(raw)
})
