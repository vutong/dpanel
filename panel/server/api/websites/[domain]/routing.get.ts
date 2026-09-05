import { requireAuth } from '../../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled, readCachePayload } from '../../../utils/cache-read'
import { assertNodeSite, normalizeSiteDomain } from '../../../utils/sites'
import { readSiteRouting, routingConfigExists } from '../../../utils/site-routing'
import { runScript } from '../../../utils/stack'

type HostIpCache = { ip?: string }

async function detectServerIpLegacy(): Promise<string> {
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
  let serverIp = ''

  if (cacheReadEnabled()) {
    const { payload, result } = await readCachePayload<HostIpCache>('host-ip.json', event)
    serverIp = String(payload?.ip || '').trim()
    return attachCacheMeta(
      {
        ok: true,
        domain,
        routing: { wildcardBase: routing.wildcardBase },
        configured: await routingConfigExists(domain),
        serverIp
      },
      result
    )
  }

  serverIp = await detectServerIpLegacy()
  return {
    ok: true,
    domain,
    routing: { wildcardBase: routing.wildcardBase },
    configured: await routingConfigExists(domain),
    serverIp
  }
})
