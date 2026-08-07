import { requireAuth } from '../../utils/auth-guard'
import { deleteApiKey } from '../../utils/api-keys'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const id = String(getRouterParam(event, 'id') || '').trim()
  if (!id) {
    throw createError({ statusCode: 400, statusMessage: 'Missing id' })
  }
  await deleteApiKey(id)
  return { ok: true }
})
