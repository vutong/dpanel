import { requireAuth } from '../../../utils/auth-guard'
import { cacheReadEnabled } from '../../../utils/cache-read'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/sites'
import {
  getAppDirSizeBytes,
  readSiteResources,
  readSiteResourcesCache
} from '../../../utils/site-resources'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  if (cacheReadEnabled()) {
    const cached = await readSiteResourcesCache(domain)
    if (cached.data) {
      return {
        domain,
        config: cached.data.config,
        appDirBytes: cached.data.appDirBytes
      }
    }
    const config = await readSiteResources(domain)
    return { domain, config, appDirBytes: null }
  }

  const config = await readSiteResources(domain)
  const appDirBytes = await getAppDirSizeBytes(domain)
  return { domain, config, appDirBytes }
})
