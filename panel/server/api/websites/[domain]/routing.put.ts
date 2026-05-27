import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/site-env'
import {
  computeServerNames,
  readSiteRouting,
  writeSiteRouting,
  type SiteRoutingConfig
} from '../../../utils/site-routing'
import { runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  const body = await readBody<{
    wildcardBase?: string
    extraDomains?: string[]
  }>(event).catch(() => ({}))

  const input: SiteRoutingConfig = {
    wildcardBase: String(body?.wildcardBase ?? ''),
    extraDomains: Array.isArray(body?.extraDomains)
      ? body.extraDomains.map((d) => String(d))
      : []
  }

  const saved = await writeSiteRouting(domain, input)

  try {
    await runScript('site-routing-apply.sh', [domain], 60_000)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'nginx apply failed'
    throw createError({
      statusCode: 500,
      statusMessage: `Routing saved but nginx reload failed: ${msg}`
    })
  }

  const routing = await readSiteRouting(domain)
  return {
    ...saved,
    serverNames: computeServerNames(domain, routing)
  }
})
