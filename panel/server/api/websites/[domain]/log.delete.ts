import { requireAuth } from '../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../utils/site-env'
import { parseScriptJson, runScript, type SiteLogKind } from '../../../utils/stack'

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
    const out = await runScript('site-log-clear.sh', [domain, op], 30_000)
    return parseScriptJson<{ ok: boolean; domain?: string; op?: string }>(out)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Could not clear log'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
