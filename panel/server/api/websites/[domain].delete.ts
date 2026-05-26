import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript, scriptErrorMessage } from '../../utils/stack'

type SiteDeleteResult = {
  ok: boolean
  domain?: string
  purged?: boolean
  removed?: string[]
  error?: string
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  try {
    const out = await runScript('site-delete.sh', [domain], 120_000)
    const result = parseScriptJson<SiteDeleteResult>(out)
    if (!result.ok) {
      throw createError({
        statusCode: 500,
        statusMessage: result.error || 'Failed to remove website'
      })
    }
    return result
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'statusCode' in e) throw e
    throw createError({ statusCode: 500, statusMessage: scriptErrorMessage(e) })
  }
})
