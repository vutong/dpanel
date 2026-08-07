import { readBody } from 'h3'
import { requireAuth } from '../../utils/auth-guard'
import { createApiKey } from '../../utils/api-keys'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ label?: string; permission?: string }>(event).catch(() => ({}))
  const created = await createApiKey({
    label: body?.label,
    permission: body?.permission,
  })
  return created
})
