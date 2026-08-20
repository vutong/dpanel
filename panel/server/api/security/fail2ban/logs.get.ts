import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const query = getQuery(event)
  const lines = Math.min(Math.max(Number(query.lines) || 200, 1), 2000)
  const grep = String(query.grep || '').trim()

  const args = [String(lines)]
  if (grep) args.push(grep)

  try {
    const raw = await runScript('host-fail2ban-logs.sh', args, 60_000)
    return parseScriptJson<{
      ok: boolean
      lines: string[]
      truncated: boolean
      path: string | null
      warning?: string
    }>(raw)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
