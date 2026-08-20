import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-fail2ban-start.sh', [], 90_000)
    const result = parseScriptJson<{
      ok: boolean
      started?: boolean
      active?: boolean
      error?: string
      detail?: string
    }>(raw)
    if (!result.ok) {
      return {
        ok: false,
        error: result.detail
          ? `${result.error || 'Start failed'}: ${result.detail.slice(0, 500)}`
          : result.error || 'Start failed',
        ...result
      }
    }
    return result
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e)
    }
  }
})
