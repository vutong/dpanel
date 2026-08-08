import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript, runScriptDetached, stackRoot } from '../../utils/stack'
import { getSite, isSitePendingDelete, normalizeSiteDomain } from '../../utils/sites'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const forever = String(getQuery(event).forever || '') === '1'

  const script = join(stackRoot(), 'infra', 'scripts', 'site-delete.sh')
  try {
    await access(script)
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'site-delete.sh not found — run: sudo dpanel update' })
  }

  const site = await getSite(domain)

  if (forever) {
    if (!isSitePendingDelete(site)) {
      throw createError({
        statusCode: 409,
        statusMessage: 'Delete forever is only allowed while the site is pending delete — soft-delete first'
      })
    }
    runScriptDetached('site-delete.sh', [domain, '--purge'])
    return {
      ok: true,
      accepted: true,
      background: true,
      soft: false,
      purged: true,
      domain
    }
  }

  try {
    const out = await runScript('site-delete.sh', [domain, '--soft'], 60_000)
    const result = parseScriptJson<{
      ok?: boolean
      domain?: string
      soft?: boolean
      expiresAt?: string
    }>(out)
    return {
      ok: true,
      accepted: true,
      soft: true,
      domain: result.domain || domain,
      expiresAt: result.expiresAt || null
    }
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Soft delete failed'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
