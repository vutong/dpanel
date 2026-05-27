import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/site-env'
import { readSiteRouting, routingConfigExists } from '../../../utils/site-routing'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  const routing = await readSiteRouting(domain)
  return {
    ok: true,
    domain,
    routing: { wildcardBase: routing.wildcardBase },
    configured: await routingConfigExists(domain)
  }
})
