import { requireAuth } from '../../../utils/auth-guard'
import { collectBannedIps } from '../../../utils/fail2ban-ip-utils'
import { queryFail2ban, syncFail2banBanEventsFromIps } from '../../../utils/fail2ban-host'
import { scriptErrorMessage } from '../../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  try {
    const host = await queryFail2ban('banned')
    if (!host.installed) {
      return {
        ok: false,
        error: 'Fail2ban is not installed',
        jails: [],
        bannedIps: [],
        ipGeo: {},
        geoip: emptyGeoip()
      }
    }

    syncFail2banBanEventsFromIps(host.bannedIps)

    let ipGeo = {}
    let geoip = emptyGeoip()
    try {
      const { getGeoipStatus, lookupIpGeoBatch } = await import('../../../utils/geoip')
      ipGeo = lookupIpGeoBatch(collectBannedIps(host.jails, host.bannedIps))
      const geoStatus = getGeoipStatus()
      geoip = {
        ready: geoStatus.ready,
        syncedAt: geoStatus.meta?.syncedAt ?? null,
        buildDate: geoStatus.meta?.buildDate ?? null,
        edition: geoStatus.meta?.edition ?? null,
        filename: geoStatus.meta?.filename ?? null
      }
    } catch {
      /* keep banned list working even if GeoIP module/database is unavailable */
    }

    return {
      ok: true,
      active: host.active,
      jails: host.jails,
      bannedIps: host.bannedIps,
      ipGeo,
      geoip
    }
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e),
      jails: [],
      bannedIps: [],
      ipGeo: {},
      geoip: emptyGeoip()
    }
  }
})

function emptyGeoip() {
  return {
    ready: false,
    syncedAt: null,
    buildDate: null,
    edition: null,
    filename: null
  }
}
