import { requireAuth } from '../../utils/auth-guard'
import { runScript } from '../../utils/stack'

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
  if (githubUrl) {
    args.push(githubUrl)
    if (githubToken) args.push(githubToken)
  }

  try {
    const out = await runScript('site-create.sh', args, 300_000)
    const result = JSON.parse(out.split('\n').pop() || out)
    return result
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Failed to create website'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
