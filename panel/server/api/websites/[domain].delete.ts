import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../utils/stack'

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
  const purge = getQuery(event).purge === '1' || getQuery(event).purge === 'true'

  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const args = [domain]
  if (purge) args.push('--purge')

  try {
    const out = await runScript('site-delete.sh', args, 180_000)
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
    const msg = e instanceof Error ? e.message : 'Failed to remove website'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
