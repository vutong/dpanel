import { createError } from 'h3'
import { computeServerNames, readSiteRouting } from './site-routing'
import { runScript } from './stack'

/**
 * Write is already on disk; wait until nginx vhost + reload finish.
 * Internal routing APIs used to `runScriptDetached` and return ok while
 * `00-default-404.conf` still answered the custom hostname.
 */
export async function applySiteRoutingNow(siteDomain: string) {
  try {
    await runScript('site-routing-apply.sh', [siteDomain], 60_000)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'nginx apply failed'
    throw createError({
      statusCode: 500,
      statusMessage: `Routing saved but nginx reload failed: ${msg}`
    })
  }
  const routing = await readSiteRouting(siteDomain)
  return {
    applied: true as const,
    extraDomains: routing.extraDomains,
    serverNames: computeServerNames(siteDomain, routing)
  }
}
