import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import {
  bantimeIncrementAllowed,
  bantimeIncrementMaxSeconds,
  defaultBantimeIncrementForJail
} from './fail2ban-bantime'
import { stackRoot } from './stack'

export type Fail2banJailSettings = {
  enabled: boolean
  maxretry: number
  findtime: number
  bantime: number
  /** Native fail2ban bantime.increment with stepped multipliers (not for nginx-php-exploit). */
  bantimeIncrement?: boolean
}

export type Fail2banSettings = {
  ignoreip: string[]
  jails: Record<string, Fail2banJailSettings>
}

export const DPANEL_JAILS = ['nginx-dpanel-login', 'nginx-php-exploit'] as const

export const DEFAULT_FAIL2BAN_SETTINGS: Fail2banSettings = {
  ignoreip: ['127.0.0.1/8', '::1'],
  jails: {
    sshd: {
      enabled: true,
      maxretry: 5,
      findtime: 600,
      bantime: 3600,
      bantimeIncrement: true
    },
    'nginx-dpanel-login': {
      enabled: true,
      maxretry: 5,
      findtime: 600,
      bantime: 3600,
      bantimeIncrement: true
    },
    'nginx-php-exploit': {
      enabled: true,
      maxretry: 10,
      findtime: 600,
      bantime: 7200,
      bantimeIncrement: false
    }
  }
}

export function fail2banSettingsPath(): string {
  return join(stackRoot(), 'data', 'panel', 'fail2ban-settings.json')
}

function normalizeJailSettings(
  name: string,
  cfg: Partial<Fail2banJailSettings> | undefined,
  fallback: Fail2banJailSettings
): Fail2banJailSettings {
  const prev = fallback
  const incrementRaw = cfg?.bantimeIncrement
  const bantimeIncrement =
    bantimeIncrementAllowed(name) &&
    (typeof incrementRaw === 'boolean' ? incrementRaw : defaultBantimeIncrementForJail(name))

  return {
    enabled: cfg?.enabled !== false,
    maxretry: Number(cfg?.maxretry) || prev.maxretry,
    findtime: Number(cfg?.findtime) || prev.findtime,
    bantime: Number(cfg?.bantime) || prev.bantime,
    bantimeIncrement
  }
}

export function readFail2banSettings(): Fail2banSettings {
  const path = fail2banSettingsPath()
  if (!existsSync(path)) {
    return structuredClone(DEFAULT_FAIL2BAN_SETTINGS)
  }
  try {
    const raw = readFileSync(path, 'utf8')
    const parsed = JSON.parse(raw) as Partial<Fail2banSettings>
    return mergeFail2banSettings(parsed)
  } catch {
    return structuredClone(DEFAULT_FAIL2BAN_SETTINGS)
  }
}

export function mergeFail2banSettings(partial: Partial<Fail2banSettings>): Fail2banSettings {
  const base = structuredClone(DEFAULT_FAIL2BAN_SETTINGS)
  if (Array.isArray(partial.ignoreip) && partial.ignoreip.length) {
    base.ignoreip = partial.ignoreip.map(String)
  }
  if (partial.jails && typeof partial.jails === 'object') {
    for (const [name, cfg] of Object.entries(partial.jails)) {
      if (!cfg || typeof cfg !== 'object') continue
      const prev = base.jails[name] || DEFAULT_FAIL2BAN_SETTINGS.jails.sshd
      base.jails[name] = normalizeJailSettings(name, cfg, prev)
    }
  }
  return base
}

const IP_RE =
  /^(?:(?:25[0-5]|2[0-4]\d|[01]?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|[01]?\d?\d)){3}(?:\/(?:3[0-2]|[12]?\d))?|(?:[0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}(?:\/(?:12[0-8]|1[01]\d|\d?\d))?)$/

const JAIL_NAME_RE = /^[a-zA-Z0-9._-]+$/

export function validateFail2banSettings(
  input: unknown
): { ok: true; settings: Fail2banSettings } | { ok: false; error: string } {
  if (!input || typeof input !== 'object') {
    return { ok: false, error: 'Invalid settings body' }
  }
  const body = input as Partial<Fail2banSettings>
  const settings = mergeFail2banSettings(body)

  if (!Array.isArray(settings.ignoreip) || !settings.ignoreip.length) {
    return { ok: false, error: 'ignoreip must contain at least one entry' }
  }
  for (const ip of settings.ignoreip) {
    const s = String(ip).trim()
    if (!IP_RE.test(s)) {
      return { ok: false, error: `Invalid ignoreip: ${s}` }
    }
  }

  for (const [name, cfg] of Object.entries(settings.jails)) {
    if (!JAIL_NAME_RE.test(name)) {
      return { ok: false, error: `Invalid jail name: ${name}` }
    }
    if (cfg.maxretry < 1 || cfg.maxretry > 20) {
      return { ok: false, error: `${name}: maxretry must be 1–20` }
    }
    if (cfg.findtime < 60 || cfg.findtime > 86400) {
      return { ok: false, error: `${name}: findtime must be 60–86400 seconds` }
    }
    const bantimeMax = cfg.bantimeIncrement ? 86400 : 86400
    if (cfg.bantime < 60 || cfg.bantime > bantimeMax) {
      return { ok: false, error: `${name}: bantime must be 60–${bantimeMax} seconds` }
    }
    if (cfg.bantimeIncrement && !bantimeIncrementAllowed(name)) {
      return { ok: false, error: `${name}: incremental bantime is not supported for this jail` }
    }
    if (cfg.bantimeIncrement) {
      const maxtime = bantimeIncrementMaxSeconds(cfg.bantime)
      if (maxtime > 15_552_000) {
        return { ok: false, error: `${name}: incremental max bantime exceeds Fail2ban limit` }
      }
    }
  }

  return { ok: true, settings }
}

export function writeFail2banSettings(settings: Fail2banSettings): void {
  const path = fail2banSettingsPath()
  mkdirSync(join(stackRoot(), 'data', 'panel'), { recursive: true })
  writeFileSync(path, `${JSON.stringify(settings, null, 2)}\n`, 'utf8')
}

export function seedFail2banSettingsIfMissing(): void {
  const path = fail2banSettingsPath()
  if (existsSync(path)) return
  writeFail2banSettings(DEFAULT_FAIL2BAN_SETTINGS)
}

export function resetJailToDefault(jailName: string): Fail2banSettings {
  const settings = readFail2banSettings()
  const def = DEFAULT_FAIL2BAN_SETTINGS.jails[jailName]
  if (def) {
    settings.jails[jailName] = structuredClone(def)
  } else {
    delete settings.jails[jailName]
  }
  writeFail2banSettings(settings)
  return settings
}
