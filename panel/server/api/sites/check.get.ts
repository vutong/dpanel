import { getQuery } from 'h3'
import { requireApiCredentials } from '../../utils/api-auth'
import { isDomainAvailable } from '../../utils/domain-occupancy'

// Future (not implemented): site lifecycle for platform automation
// POST   /api/sites
// DELETE /api/sites/:domain
// POST   /api/sites/:domain/suspend
// These manage dpanel Node sites (container/nginx), not Dutabi Store tenants.

export default defineEventHandler(async (event) => {
  await requireApiCredentials(event, 'read')

  const query = getQuery(event)
  const domain = String(query.domain || '').trim()
  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'domain query is required' })
  }

  const available = await isDomainAvailable(domain)
  return { available }
})
