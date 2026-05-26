import { requireAuth } from '../../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  try {
    const out = await runScript('site-rebuild.sh', [domain], 600_000)
    return parseScriptJson(out)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Failed to rebuild site'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
