import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/sites'
import { runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  try {
    const raw = await runScript('site-routing-sync.sh', [domain], 180_000)
    return { ok: true, domain, message: raw || 'Custom domains reconciled' }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Sync failed'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
