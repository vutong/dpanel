import { requireAuth } from '../../../utils/auth-guard'
import { runScriptDetached, stackRoot } from '../../../utils/stack'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const script = join(stackRoot(), 'infra', 'scripts', 'site-rebuild.sh')
  try {
    await access(script)
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'site-rebuild.sh not found — run: sudo dpanel update' })
  }

  runScriptDetached('site-rebuild.sh', [domain], {}, domain, 'rebuild')

  return {
    ok: true,
    accepted: true,
    background: true,
    domain,
    op: 'rebuild'
  }
})
