import { readSitesRegistry } from './sites'
import { normalizeHostname, readSiteRouting } from './site-routing'

/**
 * Exact hostname occupancy across all sites (primary, extraDomains, wildcard apex/www).
 * Does NOT treat every host under *.wildcardBase as taken — hub storefronts use that wildcard.
 */
export async function isDomainAvailable(rawDomain: string): Promise<boolean> {
  const host = normalizeHostname(rawDomain)
  if (!host) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid domain' })
  }

  const sites = await readSitesRegistry().catch(() => [] as Awaited<ReturnType<typeof readSitesRegistry>>)

  for (const site of sites) {
    const primary = normalizeHostname(site.domain || '')
    if (primary && primary === host) return false

    const routing = await readSiteRouting(site.domain || '')
    if (routing.extraDomains.includes(host)) return false

    if (routing.wildcardBase) {
      if (host === routing.wildcardBase) return false
      if (host === `www.${routing.wildcardBase}`) return false
    }
  }

  return true
}
