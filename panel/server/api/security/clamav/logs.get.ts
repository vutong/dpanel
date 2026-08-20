import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const query = getQuery(event)
  const lines = Math.min(Math.max(Number(query.lines) || 200, 1), 2000)
  const grep = String(query.grep || '').trim()
  const source = String(query.source || 'clamav').trim().toLowerCase()
  const allowed = ['clamav', 'freshclam', 'clamd', 'scan']
  const logSource = allowed.includes(source) ? source : 'clamav'

  const args = [String(lines)]
  if (grep) args.push(grep)
  args.push(logSource)

  try {
    const raw = await runScript('host-clamav-logs.sh', args, 60_000)
    return parseScriptJson<{
      ok: boolean
      lines: string[]
      truncated: boolean
      path: string | null
      source: string
      warning?: string
    }>(raw)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
