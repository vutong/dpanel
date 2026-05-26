import { requireAuth } from '../../../utils/auth-guard'
import { normalizeSiteDomain, readSiteEnv } from '../../../utils/site-env'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  return readSiteEnv(domain)
})
