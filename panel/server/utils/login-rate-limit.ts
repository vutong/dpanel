import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import type { H3Event } from 'h3'
import { getRequestIP, setHeader } from 'h3'
import { stackRoot } from './stack'

const WINDOW_MS = 15 * 60 * 1000
const MAX_FAILURES = 5
const LOCK_MS = 15 * 60 * 1000

type AttemptRecord = {
  failures: number[]
  lockedUntil: number | null
}

type Store = Record<string, AttemptRecord>

function storePath(): string {
  return join(stackRoot(), 'data', 'panel', 'login-attempts.json')
}

function ensureStore(): void {
  const dir = join(stackRoot(), 'data', 'panel')
  mkdirSync(dir, { recursive: true })
  if (!existsSync(storePath())) {
    writeFileSync(storePath(), '{}\n', 'utf8')
  }
}

function readStore(): Store {
  ensureStore()
  try {
    return JSON.parse(readFileSync(storePath(), 'utf8')) as Store
  } catch {
    return {}
  }
}

function writeStore(store: Store): void {
  ensureStore()
  writeFileSync(storePath(), `${JSON.stringify(store)}\n`, 'utf8')
}

function clientIp(event: H3Event): string {
  return getRequestIP(event, { xForwardedFor: true }) || 'unknown'
}

function pruneFailures(failures: number[], now: number): number[] {
  return failures.filter((t) => now - t < WINDOW_MS)
}

/** Throws 429 if IP is locked or over failure budget. */
export function assertLoginAllowed(event: H3Event): string {
  const ip = clientIp(event)
  const now = Date.now()
  const store = readStore()
  const rec = store[ip] || { failures: [], lockedUntil: null }

  if (rec.lockedUntil != null && rec.lockedUntil > now) {
    const retrySec = Math.ceil((rec.lockedUntil - now) / 1000)
    setHeader(event, 'Retry-After', String(retrySec))
    throw createError({
      statusCode: 429,
      statusMessage: 'Too many failed login attempts — try again later'
    })
  }

  rec.failures = pruneFailures(rec.failures, now)
  if (rec.failures.length >= MAX_FAILURES) {
    rec.lockedUntil = now + LOCK_MS
    store[ip] = rec
    writeStore(store)
    setHeader(event, 'Retry-After', String(Math.ceil(LOCK_MS / 1000)))
    throw createError({
      statusCode: 429,
      statusMessage: 'Too many failed login attempts — try again later'
    })
  }

  store[ip] = rec
  writeStore(store)
  return ip
}

export function recordLoginFailure(event: H3Event): void {
  const ip = clientIp(event)
  const now = Date.now()
  const store = readStore()
  const rec = store[ip] || { failures: [], lockedUntil: null }
  rec.failures = pruneFailures(rec.failures, now)
  rec.failures.push(now)
  if (rec.failures.length >= MAX_FAILURES) {
    rec.lockedUntil = now + LOCK_MS
  }
  store[ip] = rec
  writeStore(store)
}

export function clearLoginFailures(event: H3Event): void {
  const ip = clientIp(event)
  const store = readStore()
  if (store[ip]) {
    delete store[ip]
    writeStore(store)
  }
}

export function isLoginLocked(event: H3Event): boolean {
  const ip = clientIp(event)
  const now = Date.now()
  const store = readStore()
  const rec = store[ip]
  if (!rec) return false
  if (rec.lockedUntil != null && rec.lockedUntil > now) return true
  rec.failures = pruneFailures(rec.failures, now)
  return rec.failures.length >= MAX_FAILURES
}
