import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import { deleteInSite } from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const body = await readBody<{ paths?: string[] }>(event).catch(() => ({}))
  return deleteInSite(domain, body?.paths)
})
