import { requireAuth } from '../../../utils/auth-guard'
import {
  beginClamavScan,
  completeSyncScan,
  getActiveScan,
  resolveClamavScanSummary
} from '../../../utils/clamav-scans'
import { runClamScan } from '../../../utils/host-security'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ domain?: string; background?: boolean }>(event).catch(() => ({}))
  const domain = String(body?.domain || '').trim().toLowerCase()
  const background = body?.background !== false

  if (domain && !/^[a-z0-9.-]+$/.test(domain)) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid domain' })
  }

  if (background) {
    try {
      const result = beginClamavScan(domain || undefined)
      if (!result.accepted) {
        const active = getActiveScan()
        throw createError({
          statusCode: 409,
          statusMessage: result.message || 'Scan already running',
          data: { activeScan: active ? resolveClamavScanSummary(active) : null }
        })
      }
      return {
        ...result,
        background: true,
        target: domain || 'all'
      }
    } catch (e: unknown) {
      if (e && typeof e === 'object' && 'statusCode' in e) throw e
      throw createError({
        statusCode: 500,
        statusMessage: e instanceof Error ? e.message : 'Could not start scan'
      })
    }
  }

  try {
    const result = await runClamScan(domain || undefined)
    const detail = completeSyncScan(domain || undefined, result)
    return {
      ...result,
      background: false,
      scanId: detail.id
    }
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: e instanceof Error ? e.message : 'Scan failed'
    })
  }
})
