import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ ip?: string; jail?: string }>(event)
  const ip = String(body?.ip || '').trim()
  if (!ip) {
    return { ok: false, error: 'ip is required' }
  }

  const args = [ip]
  if (body?.jail) args.push(String(body.jail).trim())

  try {
    const raw = await runScript('host-fail2ban-unban.sh', args, 30_000)
    const result = parseScriptJson<{ ok: boolean; ip: string; jail?: string; error?: string }>(raw)
    if (!result.ok) {
      return { ok: false, error: result.error || 'Unban failed', ...result }
    }
    return result
  } catch (e: unknown) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : 'Unban failed'
    }
  }
})
