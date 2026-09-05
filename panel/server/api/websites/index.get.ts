import { requireAuth } from '../../utils/auth-guard'
import { readSitesJson } from '../../utils/cache-store'
import { withPendingMeta, type SiteRecord } from '../../utils/sites'

/** Live sites registry — no cache (business page). */
export default defineEventHandler(async (event) => {
  requireAuth(event)

  const raw = await readSitesJson<SiteRecord[]>()
  if (raw === null) {
    throw createError({ statusCode: 500, statusMessage: 'sites.json not found or invalid' })
  }

  const sites = (Array.isArray(raw) ? raw : []).map((s) => withPendingMeta(s))
  return { sites }
})
