import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-fail2ban-reload.sh', [], 60_000)
    return parseScriptJson<{ ok: boolean; reloaded?: boolean; error?: string }>(raw)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
