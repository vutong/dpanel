import { requireAuth } from '../../../utils/auth-guard'
import { requestForceRefresh } from '../../../utils/cache-meta'
import { assertNodeSite, assertSiteActive, getSite, normalizeSiteDomain } from '../../../utils/sites'
import { writeSiteResources } from '../../../utils/site-resources'
import { runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)
  assertSiteActive(await getSite(domain))

  const body = await readBody<{
    cpuLimit?: number
    memoryMb?: number
    diskGb?: number
  }>(event).catch(() => ({}))

  const saved = await writeSiteResources(domain, {
    cpuLimit: body?.cpuLimit,
    memoryMb: body?.memoryMb,
    diskGb: body?.diskGb
  })

  try {
    await runScript('site-resources-apply.sh', [domain], 120_000)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Could not apply container limits'
    throw createError({
      statusCode: 500,
      statusMessage: `Limits saved but container update failed: ${msg}`
    })
  }

  await requestForceRefresh('site-resources')
  return { domain, config: saved, appDirBytes: null }
})
