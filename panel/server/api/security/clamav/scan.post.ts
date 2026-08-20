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
    return { ok: false, error: 'Invalid domain' }
  }

  if (background) {
    try {
      const result = beginClamavScan(domain || undefined)
      if (!result.accepted) {
        const active = getActiveScan()
        return {
          ok: false,
          accepted: false,
          error: result.message || 'Scan already running',
          activeScan: active ? resolveClamavScanSummary(active) : null
        }
      }
      return {
        ok: true,
        ...result,
        background: true,
        target: domain || 'all'
      }
    } catch (e: unknown) {
      return {
        ok: false,
        error: e instanceof Error ? e.message : 'Could not start scan'
      }
    }
  }

  try {
    const result = await runClamScan(domain || undefined)
    const detail = completeSyncScan(domain || undefined, result)
    return {
      ok: true,
      ...result,
      background: false,
      scanId: detail.id
    }
  } catch (e: unknown) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : 'Scan failed'
    }
  }
})
