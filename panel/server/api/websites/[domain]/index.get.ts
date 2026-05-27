import { requireAuth } from '../../../utils/auth-guard'
import { getSite, normalizeSiteDomain } from '../../../utils/sites'
import { getAppDirSizeBytes, readSiteResources } from '../../../utils/site-resources'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const site = await getSite(domain)

  let resources = null
  let appDirBytes: number | null = null
  if (site.runtime === 'node') {
    const cfg = await readSiteResources(domain)
    appDirBytes = await getAppDirSizeBytes(domain)
    resources = { ...cfg, appDirBytes }
  }

  return { site, resources }
})
