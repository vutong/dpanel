import { requireAuth } from '../../utils/auth-guard'
import { fetchHostSecurityStatus } from '../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const status = await fetchHostSecurityStatus()
    return {
      ok: true,
      installed: status.clamav?.installed ?? false,
      daemonActive: status.clamav?.daemonActive ?? false,
      freshclamActive: status.clamav?.freshclamActive ?? false,
      signatureDate: status.clamav?.signatureDate ?? null
    }
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Could not read ClamAV status'
    })
  }
})
