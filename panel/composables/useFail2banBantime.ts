/** Client-safe helpers for incremental bantime UI (mirrors server/utils/fail2ban-bantime.ts). */

export const BANTIME_INCREMENT_MULTIPLIERS = [1, 6, 24, 72, 168, 720, 4320] as const

export const JAILS_WITHOUT_BANTIME_INCREMENT = new Set(['nginx-php-exploit'])

export function bantimeIncrementAllowed(jailName: string): boolean {
  return !JAILS_WITHOUT_BANTIME_INCREMENT.has(jailName)
}

export function formatDurationSeconds(totalSec: number): string {
  if (totalSec < 3600) return `${Math.round(totalSec / 60)}m`
  if (totalSec < 86400) return `${Math.round(totalSec / 3600)}h`
  return `${Math.round(totalSec / 86400)}d`
}

export function formatBantimeIncrementLadder(baseBantime: number): string {
  return BANTIME_INCREMENT_MULTIPLIERS.map((m) => formatDurationSeconds(baseBantime * m)).join(
    ' → '
  )
}

export function defaultBantimeIncrementForJail(jailName: string): boolean {
  return jailName === 'sshd' || jailName === 'nginx-dpanel-login'
}
