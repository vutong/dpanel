import { requireAuth } from '../../../utils/auth-guard'
import { installFail2ban } from '../../../utils/host-security'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    return await installFail2ban()
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
