import { requireAuth } from '../../../utils/auth-guard'
import {
  buildGeoipStatusPayload,
  buildIpGeoMap,
  queryFail2ban,
  syncFail2banBanEventsFromIps
} from '../../../utils/fail2ban-banned'
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
        geoip: buildGeoipStatusPayload()
      }
    }

    syncFail2banBanEventsFromIps(host.bannedIps)

    const ipGeo = buildIpGeoMap(host.jails, host.bannedIps)

    return {
      ok: true,
      active: host.active,
      jails: host.jails,
      bannedIps: host.bannedIps,
      ipGeo,
      geoip: buildGeoipStatusPayload()
    }
  } catch (e: unknown) {
    return {
      ok: false,
      error: scriptErrorMessage(e),
      jails: [],
      bannedIps: [],
      ipGeo: {},
      geoip: buildGeoipStatusPayload()
    }
  }
})
