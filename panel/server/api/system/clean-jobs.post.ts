import { requireAuth } from '../../utils/auth-guard'
import { clearStuckJobs } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  return clearStuckJobs()
})
