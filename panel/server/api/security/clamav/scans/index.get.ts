import { requireAuth } from '../../../../utils/auth-guard'
import {
  getActiveScan,
  listScans,
  readScanDetail,
  recordClamavScanEventsIfNeeded,
  resolveClamavScanSummary
} from '../../../../utils/clamav-scans'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const query = getQuery(event)
  const activeOnly = String(query.active || '') === '1'
  const domain = String(query.domain || '').trim().toLowerCase()
  const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100)
  const id = String(query.id || '').trim()

  if (id) {
    let detail = readScanDetail(id)
    if (detail) {
      detail = recordClamavScanEventsIfNeeded(id) || resolveClamavScanSummary(detail)
      if (detail.status === 'running') {
        detail = resolveClamavScanSummary(detail) as typeof detail
      }
    }
    return { ok: true, scan: detail }
  }

  if (activeOnly) {
    const active = getActiveScan()
    if (active) {
      const resolved = resolveClamavScanSummary(active)
      if (resolved.status === 'running') {
        return { ok: true, scan: resolved, active: true }
      }
      recordClamavScanEventsIfNeeded(resolved.id)
    }
    return { ok: true, scan: null, active: false }
  }

  const scans = listScans({ domain: domain || undefined, limit }).map((s) => {
    const resolved = resolveClamavScanSummary(s)
    if (resolved.status !== 'running') {
      recordClamavScanEventsIfNeeded(resolved.id)
    }
    return resolved
  })

  return { ok: true, scans }
})
