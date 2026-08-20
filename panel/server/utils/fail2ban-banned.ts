import type { Fail2banJailRow } from './fail2ban-host'
import { collectBannedIps } from './fail2ban-ip-utils'
import {
  getGeoipStatus,
  lookupIpGeoBatch,
  type IpGeoEntry
} from './geoip'

export function buildIpGeoMap(
  jails: Fail2banJailRow[],
  bannedIps: string[]
): Record<string, IpGeoEntry> {
  return lookupIpGeoBatch(collectBannedIps(jails, bannedIps))
}

export function buildGeoipStatusPayload() {
  const geoStatus = getGeoipStatus()
  return {
    ready: geoStatus.ready,
    syncedAt: geoStatus.meta?.syncedAt ?? null,
    buildDate: geoStatus.meta?.buildDate ?? null,
    edition: geoStatus.meta?.edition ?? null,
    filename: geoStatus.meta?.filename ?? null
  }
}
