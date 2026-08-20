import { requireAuth } from '../../../utils/auth-guard'
import { collectBannedIps } from '../../../utils/fail2ban-ip-utils'
import { queryFail2ban } from '../../../utils/fail2ban-host'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const { getGeoipStatus, syncGeoipDatabase } = await import('../../../utils/geoip')

    let ips: string[] = []
    try {
      const host = await queryFail2ban('banned')
      if (host.installed) {
        ips = collectBannedIps(host.jails, host.bannedIps)
      }
    } catch {
      /* sync can still run with empty list (ensure file exists) */
    }

    const res = await syncGeoipDatabase(ips)
    const status = getGeoipStatus()
    return {
      ok: true,
      provider: res.provider,
      syncedAt: res.syncedAt,
      total: res.total,
      resolved: res.resolved,
      missing: res.missing,
      ready: status.ready,
      count: status.count
    }
  } catch (e: unknown) {
    return {
      ok: false,
      error: e instanceof Error ? e.message : 'GeoIP sync failed'
    }
  }
})
