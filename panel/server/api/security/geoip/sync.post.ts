import { requireAuth } from '../../../utils/auth-guard'
import { getGeoipStatus, syncGeoipDatabase } from '../../../utils/geoip'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
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
