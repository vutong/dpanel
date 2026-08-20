import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, stackRoot } from '../../../utils/stack'
import { getSite, isSiteSuspended, normalizeSiteDomain } from '../../../utils/sites'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))

  const site = await getSite(domain)
  if (!isSiteSuspended(site)) {
    throw createError({ statusCode: 409, statusMessage: 'Site is not suspended' })
  }

  const script = join(stackRoot(), 'infra', 'scripts', 'site-unsuspend.sh')
  try {
    await access(script)
  } catch {
    throw createError({
      statusCode: 500,
      statusMessage: 'site-unsuspend.sh not found — run: sudo dpanel update'
    })
  }

  try {
    const out = await runScript('site-unsuspend.sh', [domain], 120_000)
    return parseScriptJson(out)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Unsuspend failed'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
