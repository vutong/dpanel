import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{
    domain?: string
    runtime?: string
    githubUrl?: string
    githubToken?: string
  }>(event)

  const domain = (body.domain || '').trim().toLowerCase()
  const runtime = (body.runtime || '').trim().toLowerCase()
  const githubUrl = (body.githubUrl || '').trim()
  const githubToken = (body.githubToken || '').trim()

  if (!domain || !runtime) {
    throw createError({ statusCode: 400, statusMessage: 'Domain and runtime are required' })
  }
  if (runtime !== 'node' && runtime !== 'php') {
    throw createError({ statusCode: 400, statusMessage: 'Runtime must be node or php' })
  }

  const args = [domain, runtime]
  const extraEnv: Record<string, string> = {}
  if (githubUrl) {
    args.push(githubUrl)
    if (githubToken) extraEnv.GITHUB_TOKEN = githubToken
  }

  try {
    const out = await runScript('site-create.sh', args, 300_000, extraEnv)
    return parseScriptJson(out)
  } catch (e: unknown) {
    let msg =
      (e && typeof e === 'object' && 'statusMessage' in e && String((e as { statusMessage?: string }).statusMessage)) ||
      (e instanceof Error ? e.message : '') ||
      'Failed to create website'
    msg = msg.replace(/github_pat_[A-Za-z0-9_]+/g, 'github_pat_***')
    msg = msg.replace(/\bghp_[A-Za-z0-9]+\b/g, 'ghp_***')
    msg = msg.replace(/\bgho_[A-Za-z0-9]+\b/g, 'gho_***')
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
