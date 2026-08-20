import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ ip?: string; jail?: string }>(event)
  const ip = String(body?.ip || '').trim()
  if (!ip) {
    throw createError({ statusCode: 400, statusMessage: 'ip is required' })
  }

  const args = [ip]
  if (body?.jail) args.push(String(body.jail).trim())

  try {
    const raw = await runScript('host-fail2ban-unban.sh', args, 30_000)
    return parseScriptJson<{ ok: boolean; ip: string; jail?: string }>(raw)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Unban failed'
    })
  }
})
