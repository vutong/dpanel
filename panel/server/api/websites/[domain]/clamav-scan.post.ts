import { requireAuth } from '../../../utils/auth-guard'
import { beginClamavScan } from '../../../utils/clamav-scans'
import { assertSiteActive, getSite } from '../../../utils/sites'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  assertSiteActive(await getSite(domain))

  let result: ReturnType<typeof beginClamavScan>
  try {
    result = beginClamavScan(domain)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Could not start scan'
    })
  }

  if (!result.accepted) {
    throw createError({
      statusCode: 409,
      statusMessage: result.message || 'Scan already running'
    })
  }

  return {
    ...result,
    background: true,
    domain
  }
})
