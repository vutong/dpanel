import { requireAuth } from '../../../utils/auth-guard'
import { cacheReadEnabled } from '../../../utils/cache-read'
import { getSite, normalizeSiteDomain, withPendingMeta } from '../../../utils/sites'
import {
  getAppDirSizeBytes,
  readSiteResources,
  readSiteResourcesCache
} from '../../../utils/site-resources'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const site = withPendingMeta(await getSite(domain))

  let resources = null
  if (site.runtime === 'node') {
    if (cacheReadEnabled()) {
      const cached = await readSiteResourcesCache(domain)
      if (cached.data) {
        resources = { ...cached.data.config, appDirBytes: cached.data.appDirBytes }
      } else {
        const cfg = await readSiteResources(domain)
        resources = { ...cfg, appDirBytes: null }
      }
    } else {
      const cfg = await readSiteResources(domain)
      const appDirBytes = await getAppDirSizeBytes(domain)
      resources = { ...cfg, appDirBytes }
    }
  }

  return { site, resources }
})
