import { requireAuth } from '../../utils/auth-guard'
import { listApiKeys } from '../../utils/api-keys'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const keys = await listApiKeys()
  return { keys }
})
