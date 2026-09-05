import { requireAuth } from '../../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled, readCachePayloadWithFallback } from '../../../utils/cache-read'
import { collectBannedIps } from '../../../utils/fail2ban-ip-utils'
import { queryFail2ban, type Fail2banQueryResult } from '../../../utils/fail2ban-host'
import { scriptErrorMessage } from '../../../utils/stack'

type SecurityDetailCachePayload = {
  fail2banBanned?: Fail2banQueryResult
}

function emptyGeoip() {
  return {
    ready: false,
    syncedAt: null as string | null,
    provider: 'country.is' as const,
    count: 0
  }
}

export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (!cacheReadEnabled()) {
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

      let ipGeo: Record<
        string,
        { countryCode: string | null; countryName: string | null; flag: string }
      > = {}
      let geoip = emptyGeoip()
      try {
        const { getGeoipStatus, lookupIpGeoBatch } = await import('../../../utils/geoip')
        ipGeo = await lookupIpGeoBatch(collectBannedIps(host.jails, host.bannedIps))
        const geoStatus = getGeoipStatus()
        geoip = {
          ready: geoStatus.ready,
          syncedAt: geoStatus.syncedAt,
          provider: geoStatus.provider,
          count: geoStatus.count
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
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityDetailCachePayload>(
    'security-detail.json',
    event,
    async () => ({ fail2banBanned: await queryFail2ban('banned') }),
    { sections: ['settings'] }
  )
  const host = payload?.fail2banBanned

  if (!host || typeof host !== 'object') {
    const error = result.warming ? 'Warming security detail cache…' : 'Security detail cache unavailable'
    return attachCacheMeta(
      {
        ok: false,
        error,
        jails: [],
        bannedIps: [],
        ipGeo: {},
        geoip: emptyGeoip()
      },
      result
    )
  }

  if (!host.installed) {
    return attachCacheMeta(
      {
        ok: false,
        error: 'Fail2ban is not installed',
        jails: [],
        bannedIps: [],
        ipGeo: {},
        geoip: emptyGeoip()
      },
      result
    )
  }

  let ipGeo: Record<
    string,
    { countryCode: string | null; countryName: string | null; flag: string }
  > = {}
  let geoip = emptyGeoip()
  try {
    const { getGeoipStatus, lookupIpGeoBatch } = await import('../../../utils/geoip')
    ipGeo = await lookupIpGeoBatch(collectBannedIps(host.jails, host.bannedIps))
    const geoStatus = getGeoipStatus()
    geoip = {
      ready: geoStatus.ready,
      syncedAt: geoStatus.syncedAt,
      provider: geoStatus.provider,
      count: geoStatus.count
    }
  } catch {
    /* ignore geo errors */
  }

  return attachCacheMeta(
    {
      ok: host.ok !== false,
      active: host.active,
      jails: host.jails,
      bannedIps: host.bannedIps,
      ipGeo,
      geoip,
      ...(host.error ? { error: host.error } : {})
    },
    result
  )
})
