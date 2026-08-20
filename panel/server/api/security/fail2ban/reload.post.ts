import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-fail2ban-reload.sh', [], 60_000)
    const result = parseScriptJson<{ ok: boolean; reloaded?: boolean; error?: string }>(raw)
    if (!result.ok) {
      return { ok: false, error: result.error || 'Reload failed', ...result }
    }
    return result
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e)
    }
  }
})
