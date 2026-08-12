import { requireAuth } from '../../../utils/auth-guard'
import {
  beginSiteOp,
  isSiteOpProcessAlive,
  runScriptDetached,
  siteOpStatusPath,
  stackRoot,
  type SiteOpKind
} from '../../../utils/stack'
import { assertSiteNotPending, getSite } from '../../../utils/sites'
import { access, readFile } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const site = await getSite(domain)
  assertSiteNotPending(site)

  if (site.runtime !== 'php') {
    throw createError({ statusCode: 400, statusMessage: 'Fix permissions is only available for PHP sites' })
  }

  try {
    const raw = await readFile(siteOpStatusPath(domain), 'utf8')
    const status = JSON.parse(raw) as { status?: string; op?: string }
    if (status.status === 'running') {
      const op =
        status.op === 'update' || status.op === 'rebuild' || status.op === 'fix-permissions'
          ? (status.op as SiteOpKind)
          : undefined
      if (isSiteOpProcessAlive(domain, op)) {
        throw createError({
          statusCode: 409,
          statusMessage: 'A site operation is already running — wait for it to finish'
        })
      }
    }
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'statusCode' in e) throw e
    /* no status file — ok */
  }

  const script = join(stackRoot(), 'infra', 'scripts', 'site-fix-permissions.sh')
  try {
    await access(script)
  } catch {
    throw createError({
      statusCode: 500,
      statusMessage: 'site-fix-permissions.sh not found — run: sudo dpanel update'
    })
  }

  beginSiteOp(domain, 'fix-permissions', 'Fixing permissions…')
  runScriptDetached('site-fix-permissions.sh', [domain], {}, domain, 'fix-permissions')

  return {
    ok: true,
    accepted: true,
    background: true,
    domain,
    op: 'fix-permissions'
  }
})
