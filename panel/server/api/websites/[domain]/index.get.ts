import { requireAuth } from '../../../utils/auth-guard'
import { getSite, normalizeSiteDomain, withPendingMeta } from '../../../utils/sites'
import { getAppDirSizeBytes, readSiteResources } from '../../../utils/site-resources'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const site = withPendingMeta(await getSite(domain))

  let resources = null
  if (site.runtime === 'node') {
    const cfg = await readSiteResources(domain)
    const appDirBytes = await getAppDirSizeBytes(domain)
    resources = { ...cfg, appDirBytes }
  }

  return { site, resources }
})
