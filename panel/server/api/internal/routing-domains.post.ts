import { readBody } from 'h3'
import { requireApiCredentials } from '../../utils/api-auth'
import { applySiteRoutingNow } from '../../utils/apply-site-routing'
import { normalizeHostname, readSiteRouting, writeSiteRouting } from '../../utils/site-routing'
import { assertNodeSite, assertSiteActive, getSite } from '../../utils/sites'

/** App containers register extra hostnames (e.g. store custom domains). */
export default defineEventHandler(async (event) => {
  await requireApiCredentials(event, 'read_write')

  const body = await readBody<{
    siteDomain?: string
    hostname?: string
    action?: string
  }>(event).catch(() => ({}))

  const siteDomain = normalizeHostname(String(body?.siteDomain || ''))
  const hostname = normalizeHostname(String(body?.hostname || ''))
  const action = String(body?.action || '').trim()

  if (!siteDomain) {
    throw createError({ statusCode: 400, statusMessage: 'Missing siteDomain' })
  }
  await assertNodeSite(siteDomain)
  assertSiteActive(await getSite(siteDomain))
  if (!['add', 'remove'].includes(action)) {
    throw createError({ statusCode: 400, statusMessage: 'action must be add or remove' })
  }
  if (!hostname) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid hostname' })
  }
  if (hostname === siteDomain) {
    throw createError({ statusCode: 400, statusMessage: 'hostname cannot equal site domain' })
  }

  const current = await readSiteRouting(siteDomain)
  const set = new Set(current.extraDomains)
  if (action === 'add') set.add(hostname)
  else set.delete(hostname)

  await writeSiteRouting(siteDomain, {
    wildcardBase: current.wildcardBase,
    extraDomains: [...set]
  })

  const applied = await applySiteRoutingNow(siteDomain)

  return {
    ok: true,
    siteDomain,
    hostname,
    action,
    ...applied
  }
})
