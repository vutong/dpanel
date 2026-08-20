import type { Fail2banJailRow } from './fail2ban-host'
import { filterBannedIps, isValidBanIp } from './fail2ban-ip'

export function collectBannedIps(jails: Fail2banJailRow[], bannedIps: string[]): string[] {
  const set = new Set<string>(filterBannedIps(bannedIps || []))
  for (const jail of jails || []) {
    for (const entry of jail.bannedIps || []) {
      if (isValidBanIp(entry.ip)) set.add(entry.ip)
    }
  }
  return [...set]
}
