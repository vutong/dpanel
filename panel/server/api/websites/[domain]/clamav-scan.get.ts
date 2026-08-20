import { requireAuth } from '../../../utils/auth-guard'
import {
  getActiveScan,
  getLastScanForDomain,
  resolveClamavScanSummary
} from '../../../utils/clamav-scans'
import { getSite } from '../../../utils/sites'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const site = await getSite(domain)
  if (!site) {
    throw createError({ statusCode: 404, statusMessage: 'Site not found' })
  }

  const active = getActiveScan()
  const activeResolved = active ? resolveClamavScanSummary(active) : null
  const globalScanRunning = activeResolved?.status === 'running'
  const domainScanRunning =
    globalScanRunning &&
    (activeResolved?.target === 'all' || activeResolved?.domain === domain)

  return {
    ok: true,
    domain,
    lastScan: getLastScanForDomain(domain),
    activeScan: domainScanRunning ? activeResolved : globalScanRunning ? activeResolved : null,
    globalScanRunning
  }
})
