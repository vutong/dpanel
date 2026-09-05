import { requireAuth } from '../../../utils/auth-guard'
import { requestForceRefresh } from '../../../utils/cache-meta'
import { parseScriptJson, runScript } from '../../../utils/stack'

type DbModifyResult = {
  ok: boolean
  name?: string
  user?: string
  password?: string
  action?: string
  error?: string
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const name = (getRouterParam(event, 'name') || '').trim()
  const body = await readBody<{ user?: string; password?: string }>(event).catch(() => ({}))

  if (!name) {
    throw createError({ statusCode: 400, statusMessage: 'Database name is required' })
  }

  const args = [name]
  const user = (body?.user || '').trim()
  const password = (body?.password || '').trim()
  if (user) args.push(user)
  if (password) args.push(password)

  try {
    const out = await runScript('db-modify.sh', args, 60_000)
    const result = parseScriptJson<DbModifyResult>(out)
    if (!result.ok) {
      throw createError({
        statusCode: 500,
        statusMessage: result.error || 'Failed to reset password'
      })
    }
    await requestForceRefresh('databases-list')
    return result
  } catch (e: unknown) {
    if (e && typeof e === 'object' && 'statusCode' in e) throw e
    const msg = e instanceof Error ? e.message : 'Failed to reset password'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
