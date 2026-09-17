import { requireAuth } from '../../../utils/auth-guard'
import { applySiteRoutingNow } from '../../../utils/apply-site-routing'
import { assertNodeSite, assertSiteActive, getSite, normalizeSiteDomain } from '../../../utils/sites'
import { readSiteRouting, writeSiteRouting } from '../../../utils/site-routing'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)
  assertSiteActive(await getSite(domain))

  const body = await readBody<{ wildcardBase?: string }>(event).catch(() => ({}))

  const current = await readSiteRouting(domain)
  const saved = await writeSiteRouting(domain, {
    wildcardBase: String(body?.wildcardBase ?? ''),
    extraDomains: current.extraDomains
  })

  await applySiteRoutingNow(domain)

  return saved
})
