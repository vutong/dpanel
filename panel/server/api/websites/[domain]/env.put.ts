import { requireAuth } from '../../../utils/auth-guard'
import { normalizeSiteDomain, writeSiteEnv } from '../../../utils/site-env'
import { parseScriptJson, runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const body = await readBody<{ content?: string; restart?: boolean }>(event).catch(() => ({}))

  const result = await writeSiteEnv(domain, body?.content ?? '')

  if (body?.restart) {
    try {
      const out = await runScript('site-app-restart.sh', [domain], 60_000)
      const restarted = parseScriptJson<{ ok?: boolean }>(out)
      if (!restarted.ok) {
        throw createError({ statusCode: 500, statusMessage: 'Saved .env but container restart failed' })
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Container restart failed'
      throw createError({
        statusCode: 500,
        statusMessage: `.env saved — ${msg}`
      })
    }
  }

  return { ...result, restarted: !!body?.restart }
})
