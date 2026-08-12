import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import { renameInSite } from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const body = await readBody<{ from?: string; to?: string }>(event).catch(() => ({}))
  if (!body?.from || body.to == null || String(body.to).trim() === '') {
    throw createError({ statusCode: 400, statusMessage: 'from and to are required' })
  }
  return renameInSite(domain, body.from, body.to)
})
