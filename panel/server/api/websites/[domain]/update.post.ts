import { requireAuth } from '../../../utils/auth-guard'
import { beginSiteOp, runScriptDetached, stackRoot } from '../../../utils/stack'
import { assertSiteActive, getSite, updateSiteGithubUrl } from '../../../utils/sites'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  const body = await readBody<{
    githubToken?: string
    gitDiscardLocal?: boolean
    githubUrl?: string
  }>(event).catch(() => ({}))
  const githubToken = (body?.githubToken || '').trim()
  const gitDiscardLocal = body?.gitDiscardLocal === true
  const githubUrl = (body?.githubUrl || '').trim()

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  assertSiteActive(await getSite(domain))

  if (githubUrl) {
    await updateSiteGithubUrl(domain, githubUrl)
  }

  const script = join(stackRoot(), 'infra', 'scripts', 'site-update.sh')
  try {
    await access(script)
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'site-update.sh not found — run: sudo dpanel update' })
  }

  const extraEnv: Record<string, string> = {}
  if (githubToken) extraEnv.GITHUB_TOKEN = githubToken
  if (gitDiscardLocal) extraEnv.GIT_DISCARD_LOCAL = '1'

  beginSiteOp(domain, 'update', 'Pulling from Git…')
  runScriptDetached('site-update.sh', [domain], extraEnv, domain, 'update')

  return {
    ok: true,
    accepted: true,
    background: true,
    domain,
    op: 'update'
  }
})
