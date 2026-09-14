import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import { writeTextFileInSite } from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const body = await readBody<{ path?: string; content?: string }>(event).catch(() => ({}))
  if (!body?.path) {
    throw createError({ statusCode: 400, statusMessage: 'path is required' })
  }
  return writeTextFileInSite(domain, body.path, body.content ?? '')
})
