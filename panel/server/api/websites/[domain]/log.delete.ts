import { requireAuth } from '../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../utils/sites'
import { clearSiteLog } from '../../../utils/site-log'
import type { SiteLogKind } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))

  const op = String(getQuery(event).op || '').trim() as SiteLogKind
  if (op !== 'rebuild' && op !== 'update' && op !== 'create' && op !== 'container') {
    throw createError({
      statusCode: 400,
      statusMessage: 'Query op must be rebuild, update, create, or container'
    })
  }

  try {
    return await clearSiteLog(domain, op)
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'statusCode' in e) throw e
    const msg = e instanceof Error ? e.message : 'Could not clear log'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
