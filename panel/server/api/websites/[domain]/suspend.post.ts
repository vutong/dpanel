import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript, stackRoot } from '../../../utils/stack'
import {
  getSite,
  isSitePendingDelete,
  isSiteSuspended,
  normalizeSiteDomain
} from '../../../utils/sites'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))

  const site = await getSite(domain)
  if (isSitePendingDelete(site)) {
    throw createError({
      statusCode: 409,
      statusMessage: 'Site is pending delete — cannot suspend'
    })
  }
  if (isSiteSuspended(site)) {
    return { ok: true, domain, suspended: true, already: true }
  }

  const script = join(stackRoot(), 'infra', 'scripts', 'site-suspend.sh')
  try {
    await access(script)
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'site-suspend.sh not found — run: sudo dpanel update' })
  }

  try {
    const out = await runScript('site-suspend.sh', [domain], 60_000)
    return parseScriptJson(out)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Suspend failed'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
