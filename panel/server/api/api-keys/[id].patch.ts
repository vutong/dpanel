import { readBody } from 'h3'
import { requireAuth } from '../../utils/auth-guard'
import { updateApiKeyLabel } from '../../utils/api-keys'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const id = String(getRouterParam(event, 'id') || '').trim()
  if (!id) {
    throw createError({ statusCode: 400, statusMessage: 'Missing id' })
  }
  const body = await readBody<{ label?: string }>(event).catch(() => ({}))
  const updated = await updateApiKeyLabel(id, String(body?.label || ''))
  return updated
})
