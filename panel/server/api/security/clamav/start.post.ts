import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-clamav-start.sh', [], 90_000)
    const result = parseScriptJson<{
      ok: boolean
      started?: boolean
      daemonActive?: boolean
      freshclamActive?: boolean
      error?: string
      detail?: string
    }>(raw)
    if (!result.ok) {
      const message = result.detail
        ? `${result.error || 'Start failed'}: ${result.detail.slice(0, 500)}`
        : result.error || 'Start failed'
      return { ok: false, error: message, ...result }
    }
    return result
  } catch (e: unknown) {
    return { ok: false, error: scriptErrorMessage(e) }
  }
})
