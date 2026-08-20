import { randomUUID } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { stackRoot } from './stack'

export type SecurityEventKind =
  | 'fail2ban_ban'
  | 'login_brute'
  | 'malware_found'
  | 'security_install'

export type SecurityEventSource =
  | 'fail2ban'
  | 'panel_login'
  | 'clamav'
  | 'panel'
  | 'unknown'

export type SecurityEvent = {
  id: string
  at: string
  kind: SecurityEventKind
  source: SecurityEventSource
  domain?: string | null
  ip?: string | null
  path?: string | null
  action?: string | null
  detail?: string | null
}

const MAX_EVENTS = 500

function eventsPath(): string {
  return join(stackRoot(), 'data', 'panel', 'security-events.json')
}

function ensureEventsFile(): void {
  const dir = join(stackRoot(), 'data', 'panel')
  mkdirSync(dir, { recursive: true })
  const p = eventsPath()
  if (!existsSync(p)) {
    writeFileSync(p, '[]\n', 'utf8')
  }
}

export function readSecurityEvents(): SecurityEvent[] {
  ensureEventsFile()
  try {
    const raw = readFileSync(eventsPath(), 'utf8')
    const data = JSON.parse(raw) as SecurityEvent[]
    return Array.isArray(data) ? data : []
  } catch {
    return []
  }
}

export function appendSecurityEvent(
  partial: Omit<SecurityEvent, 'id' | 'at'> & { id?: string; at?: string }
): SecurityEvent {
  ensureEventsFile()
  const events = readSecurityEvents()
  const event: SecurityEvent = {
    id: partial.id || randomUUID(),
    at: partial.at || new Date().toISOString(),
    kind: partial.kind,
    source: partial.source,
    domain: partial.domain ?? null,
    ip: partial.ip ?? null,
    path: partial.path ?? null,
    action: partial.action ?? null,
    detail: partial.detail ?? null
  }
  events.unshift(event)
  if (events.length > MAX_EVENTS) {
    events.length = MAX_EVENTS
  }
  writeFileSync(eventsPath(), `${JSON.stringify(events, null, 2)}\n`, 'utf8')
  return event
}

/** Record newly seen banned IPs from fail2ban status poll. */
export function syncFail2banBanEvents(
  bannedIps: string[],
  knownIps: Set<string>,
  jail?: string
): SecurityEvent[] {
  const added: SecurityEvent[] = []
  for (const ip of bannedIps) {
    if (!ip || knownIps.has(ip)) continue
    knownIps.add(ip)
    added.push(
      appendSecurityEvent({
        kind: 'fail2ban_ban',
        source: 'fail2ban',
        ip,
        action: 'banned_ip',
        detail: jail ? `Jail: ${jail}` : 'Fail2ban ban'
      })
    )
  }
  return added
}

export function fail2banKnownIpsPath(): string {
  return join(stackRoot(), 'data', 'panel', 'fail2ban-known-ips.json')
}

export function readFail2banKnownIps(): Set<string> {
  try {
    const raw = readFileSync(fail2banKnownIpsPath(), 'utf8')
    const list = JSON.parse(raw) as string[]
    return new Set(Array.isArray(list) ? list : [])
  } catch {
    return new Set()
  }
}

export function writeFail2banKnownIps(ips: Set<string>): void {
  const dir = join(stackRoot(), 'data', 'panel')
  mkdirSync(dir, { recursive: true })
  writeFileSync(fail2banKnownIpsPath(), `${JSON.stringify([...ips], null, 2)}\n`, 'utf8')
}
