import { requireAuth } from '../../../utils/auth-guard'
import { runClamScan } from '../../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ domain?: string }>(event).catch(() => ({}))
  const domain = String(body?.domain || '').trim().toLowerCase()

  try {
    return await runClamScan(domain || undefined)
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Scan failed'
    })
  }
})
