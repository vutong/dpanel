import { spawn, spawnSync } from 'node:child_process'
import {
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  writeFileSync
} from 'node:fs'
import { dirname, join } from 'node:path'
import { appendSecurityEvent } from './security-events'
import { scriptPath, stackRoot } from './stack'

export type ClamavScanStatus = 'running' | 'ok' | 'error'

export type ClamavInfectedHit = {
  path: string
  domain: string | null
  relPath: string
  line: string
}

export type ClamavScanSummary = {
  id: string
  target: string
  domain: string | null
  scanPath: string
  status: ClamavScanStatus
  startedAt: string
  finishedAt?: string
  infectedCount?: number
  error?: string
  eventsRecorded?: boolean
}

export type ClamavScanDetail = ClamavScanSummary & {
  infected?: ClamavInfectedHit[]
  logTail?: string
}

type ScanIndex = {
  scans: ClamavScanSummary[]
}

type DomainScanMeta = {
  lastScanId: string
  lastScanAt: string
  lastStatus: ClamavScanStatus
  lastInfectedCount: number
}

const MAX_INDEX = 100
const STUCK_GRACE_MS = 30 * 60_000

export function clamavScansDir(): string {
  return join(stackRoot(), 'data', 'panel', 'clamav-scans')
}

export function clamavScanDetailPath(id: string): string {
  return join(clamavScansDir(), `${sanitizeScanId(id)}.json`)
}

export function clamavScanLogPath(id: string): string {
  return join(stackRoot(), 'logs', 'panel', `clamav-scan-${sanitizeScanId(id)}.log`)
}

export function clamavDomainMetaPath(domain: string): string {
  return join(clamavScansDir(), 'by-domain', `${domain.replace(/[^a-zA-Z0-9.-]/g, '')}.json`)
}

function sanitizeScanId(id: string): string {
  return id.replace(/[^a-zA-Z0-9-]/g, '')
}

function ensureDirs(): void {
  mkdirSync(clamavScansDir(), { recursive: true })
  mkdirSync(join(clamavScansDir(), 'by-domain'), { recursive: true })
  mkdirSync(join(stackRoot(), 'logs', 'panel'), { recursive: true })
}

function newScanId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

export function readScanIndex(): ScanIndex {
  ensureDirs()
  const path = join(clamavScansDir(), 'index.json')
  try {
    const raw = readFileSync(path, 'utf8')
    const parsed = JSON.parse(raw) as ScanIndex
    return { scans: Array.isArray(parsed.scans) ? parsed.scans : [] }
  } catch {
    return { scans: [] }
  }
}

export function writeScanIndex(index: ScanIndex): void {
  ensureDirs()
  writeFileSync(join(clamavScansDir(), 'index.json'), JSON.stringify(index, null, 2) + '\n', 'utf8')
}

export function readScanDetail(id: string): ClamavScanDetail | null {
  try {
    const raw = readFileSync(clamavScanDetailPath(id), 'utf8')
    return JSON.parse(raw) as ClamavScanDetail
  } catch {
    return null
  }
}

export function writeScanDetail(detail: ClamavScanDetail): void {
  ensureDirs()
  writeFileSync(clamavScanDetailPath(detail.id), JSON.stringify(detail, null, 2) + '\n', 'utf8')
}

export function readDomainScanMeta(domain: string): DomainScanMeta | null {
  try {
    const raw = readFileSync(clamavDomainMetaPath(domain), 'utf8')
    return JSON.parse(raw) as DomainScanMeta
  } catch {
    return null
  }
}

export function writeDomainScanMeta(domain: string, meta: DomainScanMeta): void {
  ensureDirs()
  writeFileSync(clamavDomainMetaPath(domain), JSON.stringify(meta, null, 2) + '\n', 'utf8')
}

export function isClamavScanProcessAlive(id: string): boolean {
  const safeId = sanitizeScanId(id)
  if (!safeId) return false
  try {
    const r = spawnSync(
      'bash',
      ['-lc', `pgrep -af 'host-clamav-scan-bg\\.sh ${safeId}' >/dev/null 2>&1`],
      { timeout: 8000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

export function isAnyClamavScanProcessAlive(): boolean {
  try {
    const r = spawnSync(
      'bash',
      ['-lc', "pgrep -af 'host-clamav-scan-bg\\.sh ' >/dev/null 2>&1"],
      { timeout: 8000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

function upsertIndexSummary(summary: ClamavScanSummary): void {
  const index = readScanIndex()
  const i = index.scans.findIndex((s) => s.id === summary.id)
  if (i >= 0) {
    index.scans[i] = { ...index.scans[i], ...summary }
  } else {
    index.scans.unshift(summary)
  }
  index.scans = index.scans.slice(0, MAX_INDEX)
  writeScanIndex(index)
}

export function getActiveScan(): ClamavScanSummary | null {
  const index = readScanIndex()
  return index.scans.find((s) => s.status === 'running') ?? null
}

export function listScans(options?: { domain?: string; limit?: number }): ClamavScanSummary[] {
  const limit = Math.min(Math.max(options?.limit ?? 20, 1), 100)
  const domain = options?.domain?.trim().toLowerCase()
  let scans = readScanIndex().scans.map((s) => resolveClamavScanSummary(s))
  if (domain) {
    scans = scans.filter((s) => s.domain === domain || s.target === domain)
  }
  return scans.slice(0, limit)
}

export function resolveClamavScanSummary(summary: ClamavScanSummary): ClamavScanSummary {
  if (summary.status !== 'running') {
    return summary
  }

  if (isClamavScanProcessAlive(summary.id)) {
    return summary
  }

  const detail = readScanDetail(summary.id)
  if (detail && detail.status !== 'running') {
    upsertIndexSummary(detail)
    recordClamavScanEventsIfNeeded(detail.id)
    return detail
  }

  const startedMs = Date.parse(summary.startedAt)
  const ageMs = Date.now() - (Number.isNaN(startedMs) ? 0 : startedMs)
  if (ageMs < STUCK_GRACE_MS) {
    return summary
  }

  const failed: ClamavScanSummary = {
    ...summary,
    status: 'error',
    finishedAt: new Date().toISOString(),
    error: summary.error || 'Scan was interrupted or timed out. Check the log and try again.'
  }
  writeScanDetail({ ...failed, infected: detail?.infected, logTail: detail?.logTail })
  upsertIndexSummary(failed)
  return failed
}

export function recordClamavScanEventsIfNeeded(id: string): ClamavScanDetail | null {
  const detail = readScanDetail(id)
  if (!detail || detail.status !== 'ok' || detail.eventsRecorded) {
    return detail
  }

  for (const hit of detail.infected || []) {
    appendSecurityEvent({
      kind: 'malware_found',
      source: 'clamav',
      domain: hit.domain,
      path: hit.relPath || hit.path,
      action: 'scan_infected',
      detail: hit.line
    })
  }

  const updated: ClamavScanDetail = { ...detail, eventsRecorded: true }
  writeScanDetail(updated)
  upsertIndexSummary(updated)

  if (detail.domain) {
    writeDomainScanMeta(detail.domain, {
      lastScanId: detail.id,
      lastScanAt: detail.finishedAt || detail.startedAt,
      lastStatus: detail.status,
      lastInfectedCount: detail.infectedCount ?? 0
    })
  }

  return updated
}

export function beginClamavScan(domain?: string): {
  ok: true
  accepted: boolean
  scanId?: string
  message?: string
} {
  const normalizedDomain = domain?.trim().toLowerCase() || ''
  if (normalizedDomain && !/^[a-z0-9.-]+$/.test(normalizedDomain)) {
    throw new Error('Invalid domain')
  }

  const active = getActiveScan()
  if (active) {
    const resolved = resolveClamavScanSummary(active)
    if (resolved.status === 'running') {
      return {
        ok: true,
        accepted: false,
        message: `Scan already running (${resolved.target === 'all' ? 'all apps' : resolved.target})`
      }
    }
  }

  if (isAnyClamavScanProcessAlive()) {
    return { ok: true, accepted: false, message: 'Another scan process is still running' }
  }

  const id = newScanId()
  const target = normalizedDomain || 'all'
  const scanPath = normalizedDomain
    ? `/opt/stack/apps/${normalizedDomain}`
    : '/opt/stack/apps'

  const summary: ClamavScanDetail = {
    id,
    target,
    domain: normalizedDomain || null,
    scanPath,
    status: 'running',
    startedAt: new Date().toISOString(),
    infected: [],
    eventsRecorded: false
  }

  writeScanDetail(summary)
  upsertIndexSummary(summary)

  const logPath = clamavScanLogPath(id)
  mkdirSync(dirname(logPath), { recursive: true })
  writeFileSync(logPath, '', 'utf8')

  startClamavScanDetached(id, normalizedDomain || undefined)
  return { ok: true, accepted: true, scanId: id }
}

export function startClamavScanDetached(id: string, domain?: string): void {
  const logPath = clamavScanLogPath(id)
  mkdirSync(dirname(logPath), { recursive: true })
  const fd = openSync(logPath, 'a')
  const args = [sanitizeScanId(id)]
  if (domain) args.push(domain)
  const child = spawn('bash', [scriptPath('host-clamav-scan-bg.sh'), ...args], {
    cwd: stackRoot(),
    env: { ...process.env, STACK_ROOT: stackRoot() },
    detached: true,
    stdio: ['ignore', fd, fd]
  })
  child.unref()
}

export function getLastScanForDomain(domain: string): ClamavScanSummary | null {
  const meta = readDomainScanMeta(domain)
  if (meta?.lastScanId) {
    const detail = readScanDetail(meta.lastScanId)
    if (detail) return resolveClamavScanSummary(detail)
  }
  const fromIndex = listScans({ domain, limit: 1 })[0]
  return fromIndex ?? null
}

/** Sync scan — writes completed record immediately (legacy / foreground). */
export function completeSyncScan(
  domain: string | undefined,
  result: {
    ok: boolean
    target: string
    scanPath: string
    infectedCount: number
    infected: ClamavInfectedHit[]
    logTail?: string
    error?: string
  }
): ClamavScanDetail {
  const normalizedDomain = domain?.trim().toLowerCase() || ''
  const id = newScanId()
  const now = new Date().toISOString()
  const detail: ClamavScanDetail = {
    id,
    target: result.target,
    domain: normalizedDomain || null,
    scanPath: result.scanPath,
    status: result.ok ? 'ok' : 'error',
    startedAt: now,
    finishedAt: now,
    infectedCount: result.infectedCount,
    infected: result.infected,
    logTail: result.logTail,
    error: result.error,
    eventsRecorded: false
  }
  writeScanDetail(detail)
  upsertIndexSummary(detail)
  recordClamavScanEventsIfNeeded(id)
  return detail
}

export function clearOldScanLogs(): number {
  let cleared = 0
  const dir = join(stackRoot(), 'logs', 'panel')
  try {
    if (!existsSync(dir)) return 0
    const index = readScanIndex()
    const keep = new Set(index.scans.map((s) => `clamav-scan-${sanitizeScanId(s.id)}.log`))
    for (const name of readdirSync(dir)) {
      if (name.startsWith('clamav-scan-') && !keep.has(name)) {
        try {
          writeFileSync(join(dir, name), '', 'utf8')
          cleared += 1
        } catch {
          /* ignore */
        }
      }
    }
  } catch {
    /* ignore */
  }
  return cleared
}
