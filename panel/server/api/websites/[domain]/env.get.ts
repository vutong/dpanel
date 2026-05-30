import { requireAuth } from '../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../utils/sites'
import { readSiteEnv } from '../../../utils/site-env'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  return readSiteEnv(domain)
})
