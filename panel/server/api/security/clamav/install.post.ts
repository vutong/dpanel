import { requireAuth } from '../../../utils/auth-guard'
import { installClamAv } from '../../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    return await installClamAv()
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'ClamAV install failed'
    })
  }
})
