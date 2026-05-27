import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/site-env'
import {
  computeServerNames,
  readSiteRouting,
  routingConfigExists
} from '../../../utils/site-routing'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  const routing = await readSiteRouting(domain)
  return {
    ok: true,
    domain,
    routing,
    configured: await routingConfigExists(domain),
    serverNames: computeServerNames(domain, routing)
  }
})
