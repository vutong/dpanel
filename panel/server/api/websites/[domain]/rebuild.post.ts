import { requireAuth } from '../../../utils/auth-guard'
import { beginSiteOp, runScriptDetached, stackRoot } from '../../../utils/stack'
import { assertSiteActive, getSite } from '../../../utils/sites'
import { readBody } from 'h3'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  const body = await readBody<{ nodeModulesMode?: string }>(event).catch(() => ({}))
  const nodeModulesMode = String(body?.nodeModulesMode || 'auto').trim().toLowerCase()

  if (!['auto', 'keep', 'clean'].includes(nodeModulesMode)) {
    throw createError({ statusCode: 400, statusMessage: 'nodeModulesMode must be auto, keep, or clean' })
  }

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  assertSiteActive(await getSite(domain))

  const script = join(stackRoot(), 'infra', 'scripts', 'site-rebuild.sh')
  try {
    await access(script)
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'site-rebuild.sh not found — run: sudo dpanel update' })
  }

  beginSiteOp(domain, 'rebuild', 'Starting rebuild…')
  runScriptDetached('site-rebuild.sh', [domain], { NODE_MODULES_MODE: nodeModulesMode }, domain, 'rebuild')

  return {
    ok: true,
    accepted: true,
    background: true,
    domain,
    op: 'rebuild'
  }
})
