import { requireAuth } from '../../utils/auth-guard'
import { installHostSecurity } from '../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    return await installHostSecurity()
  } catch (e: unknown) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : 'Security install failed'
    }
  }
})
