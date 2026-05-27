import { getHeader, readBody } from 'h3'
import { normalizeHostname, readSiteRouting, writeSiteRouting } from '../../utils/site-routing'
import { assertNodeSite } from '../../utils/site-env'
import { runScriptDetached } from '../../utils/stack'

/** App containers register extra hostnames (e.g. store custom domains). */
export default defineEventHandler(async (event) => {
  const secret = String(process.env.DPANEL_INTERNAL_SECRET || '').trim()
  const hdr = String(getHeader(event, 'x-dpanel-internal') || '').trim()
  if (!secret || hdr !== secret) {
    throw createError({ statusCode: 403, statusMessage: 'Forbidden' })
  }

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

  runScriptDetached('site-routing-apply.sh', [siteDomain])

  return { ok: true, siteDomain, hostname, action }
})
