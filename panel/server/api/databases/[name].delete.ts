import { requireAuth } from '../../utils/auth-guard'
import { runScript } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const name = getRouterParam(event, 'name')
  if (!name) {
    throw createError({ statusCode: 400, statusMessage: 'Database name is required' })
  }

  try {
    const out = await runScript('db-delete.sh', [name])
    return JSON.parse(out)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Failed to delete database'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
