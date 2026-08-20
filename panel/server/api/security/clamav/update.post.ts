import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const raw = await runScript('host-clamav-update.sh', [], 600_000)
    return parseScriptJson<{ ok: boolean; message?: string; log?: string }>(raw)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'freshclam failed'
    })
  }
})
