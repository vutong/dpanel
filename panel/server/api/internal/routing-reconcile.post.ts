import { getHeader, readBody } from 'h3'
import { normalizeHostname, readSiteRouting, writeSiteRouting } from '../../utils/site-routing'

/**
 * Replace extraDomains for a Node site with the exact hostname list from the app (MongoDB).
 * Removes nginx hostnames that are no longer in the database.
 */
export default defineEventHandler(async (event) => {
  const secret = String(process.env.DPANEL_INTERNAL_SECRET || '').trim()
  const hdr = String(getHeader(event, 'x-dpanel-internal') || '').trim()
  if (!secret || hdr !== secret) {
    throw createError({ statusCode: 403, statusMessage: 'Forbidden' })
  }

  const body = await readBody<{
    siteDomain?: string
    hostnames?: string[]
  }>(event).catch(() => ({}))

  const siteDomain = normalizeHostname(String(body?.siteDomain || ''))
  if (!siteDomain) {
    throw createError({ statusCode: 400, statusMessage: 'Missing siteDomain' })
  }

  const primary = siteDomain
  const incoming = Array.isArray(body?.hostnames) ? body.hostnames : []
  const nextSet = new Set<string>()
  for (const raw of incoming) {
    const host = normalizeHostname(String(raw))
    if (!host || host === primary) continue
    nextSet.add(host)
  }

  const current = await readSiteRouting(siteDomain)
  const prevSet = new Set(current.extraDomains)

  const added = [...nextSet].filter((h) => !prevSet.has(h))
  const removed = [...prevSet].filter((h) => !nextSet.has(h))

  await writeSiteRouting(siteDomain, {
    wildcardBase: current.wildcardBase,
    extraDomains: [...nextSet]
  })

  // Nginx apply is done by site-rebuild (end) or routing.put / routing-domains — avoids double reload during Rebuild.

  return {
    ok: true,
    siteDomain,
    total: nextSet.size,
    added,
    removed
  }
})
