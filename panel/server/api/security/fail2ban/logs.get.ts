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
    const result = parseScriptJson<{
      ok: boolean
      lines: string[]
      truncated: boolean
      path: string | null
      error?: string
      warning?: string
    }>(raw)
    if (!result.ok) {
      return {
        ok: false,
        error: result.error || 'Could not load logs',
        lines: [],
        truncated: false,
        path: null,
        warning: result.warning || ''
      }
    }
    return result
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e),
      lines: [],
      truncated: false,
      path: null,
      warning: ''
    }
  }
})
