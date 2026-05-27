import { requireAuth } from '../../../utils/auth-guard'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/site-env'
import { readSiteRouting, routingConfigExists } from '../../../utils/site-routing'
import { runScript } from '../../../utils/stack'

async function detectServerIp(): Promise<string> {
  try {
    const raw = await runScript('host-ip.sh', [], 5000)
    const first = String(raw || '')
      .trim()
      .split(/\s+/)
      .find(Boolean)
    return first || ''
  } catch {
    return ''
  }
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  await assertNodeSite(domain)

  const routing = await readSiteRouting(domain)
  const serverIp = await detectServerIp()
  return {
    ok: true,
    domain,
    routing: { wildcardBase: routing.wildcardBase },
    configured: await routingConfigExists(domain),
    serverIp
  }
})
