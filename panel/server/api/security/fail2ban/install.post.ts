import { requireAuth } from '../../../utils/auth-guard'
import { installFail2ban } from '../../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    return await installFail2ban()
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Fail2ban install failed'
    })
  }
})
