import { requireAuth } from '../../utils/auth-guard'
import { runScript } from '../../utils/stack'

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
    const out = await runScript('site-delete.sh', args, 120_000)
    const result = JSON.parse(out.split('\n').pop() || out)
    return result
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Failed to remove website'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
