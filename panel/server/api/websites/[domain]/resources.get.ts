import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/sites'
import {
  getAppDirSizeBytes,
  readSiteResources
} from '../../../utils/site-resources'

/** Live site resources — no cache (business page). */
export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  const config = await readSiteResources(domain)
  const appDirBytes = await getAppDirSizeBytes(domain)
  return { domain, config, appDirBytes }
})
