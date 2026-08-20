import { requireAuth } from '../../../utils/auth-guard'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const { getGeoipStatus, syncGeoipDatabase } = await import('../../../utils/geoip')
    const res = await syncGeoipDatabase()
    const status = getGeoipStatus()
    return {
      ok: true,
      edition: res.edition,
      filename: res.filename,
      syncedAt: res.syncedAt,
      buildDate: res.buildDate ?? null,
      ready: status.ready
    }
  } catch (e: unknown) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : 'GeoIP sync failed'
    }
  }
})
