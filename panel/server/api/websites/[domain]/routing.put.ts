import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/site-env'
import { readSiteRouting, writeSiteRouting } from '../../../utils/site-routing'
import { runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  const body = await readBody<{ wildcardBase?: string }>(event).catch(() => ({}))

  const current = await readSiteRouting(domain)
  const saved = await writeSiteRouting(domain, {
    wildcardBase: String(body?.wildcardBase ?? ''),
    extraDomains: current.extraDomains
  })

  try {
    await runScript('site-routing-apply.sh', [domain], 60_000)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'nginx apply failed'
    throw createError({
      statusCode: 500,
      statusMessage: `Routing saved but nginx reload failed: ${msg}`
    })
  }

  return saved
})
