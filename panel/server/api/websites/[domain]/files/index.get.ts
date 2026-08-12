import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import { listDir } from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const path = String(getQuery(event).path || '')
  return listDir(domain, path)
})
