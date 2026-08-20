/** IP validation helpers shared by fail2ban host queries (no GeoIP / mmdb deps). */

export function isValidBanIp(ip: string): boolean {
  const s = String(ip || '').trim()
  if (!s || !/^[0-9a-fA-F:.]+$/.test(s)) return false
  if (/^\d+$/.test(s)) return false
  if (!s.includes('.') && !s.includes(':')) return false
  return true
}

export function filterBannedIps(ips: string[]): string[] {
  return (ips || []).filter(isValidBanIp)
}
