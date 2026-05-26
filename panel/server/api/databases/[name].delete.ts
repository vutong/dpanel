import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../utils/stack'

type DbDeleteResult = {
  ok: boolean
  name?: string
  droppedUser?: string | null
  error?: string
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const name = (getRouterParam(event, 'name') || '').trim()
  if (!name) {
    throw createError({ statusCode: 400, statusMessage: 'Database name is required' })
  }

  const query = getQuery(event)
  const args = [name]
  if (query.keepUser === '1' || query.keepUser === 'true') {
    args.push('--keep-user')
  }
  const user = typeof query.user === 'string' ? query.user.trim() : ''
  if (user) args.push(user)

  try {
    const out = await runScript('db-delete.sh', args, 60_000)
    const result = parseScriptJson<DbDeleteResult>(out)
    if (!result.ok) {
      throw createError({
        statusCode: 500,
        statusMessage: result.error || 'Failed to delete database'
      })
    }
    return result
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'statusCode' in e) throw e
    const msg = e instanceof Error ? e.message : 'Failed to delete database'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
