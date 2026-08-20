import { readBody } from 'h3'
import { requireApiCredentials } from '../../utils/api-auth'
import { normalizeHostname, readSiteRouting, writeSiteRouting } from '../../utils/site-routing'
import { assertNodeSite, assertSiteActive, getSite } from '../../utils/sites'
import { runScriptDetached } from '../../utils/stack'

/**
 * Replace extraDomains for a Node site with the exact hostname list from the app (MongoDB).
 * Removes nginx hostnames that are no longer in the database.
 */
export default defineEventHandler(async (event) => {
  await requireApiCredentials(event, 'read_write')

  const body = await readBody<{
    siteDomain?: string
    hostnames?: string[]
  }>(event).catch(() => ({}))

  const siteDomain = normalizeHostname(String(body?.siteDomain || ''))
  if (!siteDomain) {
    throw createError({ statusCode: 400, statusMessage: 'Missing siteDomain' })
  }
  await assertNodeSite(siteDomain)
  assertSiteActive(await getSite(siteDomain))

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

  runScriptDetached('site-routing-apply.sh', [siteDomain])

  return {
    ok: true,
    siteDomain,
    total: nextSet.size,
    added,
    removed
  }
})
