import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-clamav-update.sh', [], 600_000)
    const result = parseScriptJson<{ ok: boolean; message?: string; log?: string; error?: string }>(
      raw
    )
    if (!result.ok) {
      return { ok: false, error: result.error || result.message || 'freshclam failed' }
    }
    return result
  } catch (e: unknown) {
    return { ok: false, error: scriptErrorMessage(e) }
  }
})
