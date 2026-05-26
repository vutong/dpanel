import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

function redactGit(msg: string): string {
  return msg
    .replace(/github_pat_[A-Za-z0-9_]+/g, 'github_pat_***')
    .replace(/\bghp_[A-Za-z0-9]+\b/g, 'ghp_***')
    .replace(/\bgho_[A-Za-z0-9]+\b/g, 'gho_***')
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  const body = await readBody<{ githubToken?: string }>(event).catch(() => ({}))
  const githubToken = (body?.githubToken || '').trim()

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const extraEnv: Record<string, string> = {}
  if (githubToken) extraEnv.GITHUB_TOKEN = githubToken

  try {
    const out = await runScript('site-update.sh', [domain], 300_000, extraEnv)
    return parseScriptJson(out)
  } catch (e: unknown) {
    let msg = e instanceof Error ? e.message : 'Failed to update from Git'
    msg = redactGit(msg)
    if (/token|expired|401|403|authentication/i.test(msg)) {
      msg = `${msg} Provide a new GitHub PAT if the previous token expired.`
    }
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
