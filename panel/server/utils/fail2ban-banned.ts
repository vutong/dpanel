import type { Fail2banJailRow } from './fail2ban-host'
import { collectBannedIps } from './fail2ban-ip-utils'
import {
  getGeoipStatus,
  lookupIpGeoBatch,
  type IpGeoEntry
} from './geoip'

export async function buildIpGeoMap(
  jails: Fail2banJailRow[],
  bannedIps: string[]
): Promise<Record<string, IpGeoEntry>> {
  return lookupIpGeoBatch(collectBannedIps(jails, bannedIps))
}

export function buildGeoipStatusPayload() {
  const geoStatus = getGeoipStatus()
  return {
    ready: geoStatus.ready,
    syncedAt: geoStatus.syncedAt,
    provider: geoStatus.provider,
    count: geoStatus.count
  }
}
