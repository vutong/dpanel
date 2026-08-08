import { execFile, spawn, spawnSync } from 'node:child_process'
import {
  chmodSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync
} from 'node:fs'
import { promisify } from 'node:util'
import { readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'

const execFileAsync = promisify(execFile)

export function stackRoot(): string {
  return process.env.STACK_ROOT || '/opt/stack'
}

export function scriptPath(name: string): string {
  return join(stackRoot(), 'infra', 'scripts', name)
}

/** Extract human-readable error from bash script stderr/stdout (incl. JSON die lines). */
export function scriptErrorMessage(err: unknown): string {
  if (!err || typeof err !== 'object') {
    return 'Script failed'
  }
  const e = err as {
    message?: string
    stderr?: string | Buffer
    stdout?: string | Buffer
  }
  const blob = [String(e.stdout || ''), String(e.stderr || '')].filter(Boolean).join('\n')
  const jsonLines = blob
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('{'))
  const last = jsonLines[jsonLines.length - 1]
  if (last) {
    try {
      const j = JSON.parse(last) as { error?: string; ok?: boolean }
      if (j.error) return j.error
    } catch {
      /* ignore */
    }
  }
  const lines = blob
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith('['))
  const tail = lines.slice(-8).join(' — ')
  if (tail) return tail.slice(0, 2000)
  return (e.message || 'Script failed').replace(/^Command failed:.*\n?/i, '').trim() || 'Script failed'
}

function siteLogBasename(domain: string, op: string): string {
  const slug = domain.replace(/\./g, '-').replace(/[^a-zA-Z0-9-]/g, '')
  return `site-${op}-${slug}.log`
}

export type SiteOpKind = 'update' | 'rebuild'

/** Log sources for the site log viewer (Eye). */
export type SiteLogKind = SiteOpKind | 'create' | 'container'

export function domainSlug(domain: string): string {
  return domain.replace(/\./g, '-').replace(/[^a-zA-Z0-9-]/g, '')
}

export function siteOpLogPath(domain: string, op: Exclude<SiteLogKind, 'container'>): string {
  const slug = domainSlug(domain)
  const base = join(stackRoot(), 'logs', 'node')
  if (op === 'create') {
    return join(base, `site-create-${slug}.log`)
  }
  return join(base, `site-${op}-${slug}.log`)
}

export type SystemUpdateStatus = {
  op?: 'update'
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
  updatedAt?: string
}

/**
 * Clear any prior run (force-kill + lock + log) before starting update/rebuild.
 * Always restarts from scratch — never attaches to a stuck job.
 */
export function beginSiteOp(domain: string, op: SiteOpKind, message: string): void {
  const safeDomain = domain.replace(/[^a-zA-Z0-9.-]/g, '')
  // Kill in-flight pull/rebuild for this site (and shared site-ops lock holders).
  spawnSync(
    'bash',
    [
      '-lc',
      [
        `pkill -9 -f 'site-update\\.sh ${safeDomain}' 2>/dev/null || true`,
        `pkill -9 -f 'site-rebuild\\.sh ${safeDomain}' 2>/dev/null || true`,
        'sleep 0.2'
      ].join('; ')
    ],
    { timeout: 12_000, encoding: 'utf8' }
  )

  try {
    rmSync(join(stackRoot(), 'data', 'panel', '.site-ops.lock'), { recursive: true, force: true })
  } catch {
    /* ignore */
  }

  const logPath = siteOpLogPath(domain, op)
  mkdirSync(dirname(logPath), { recursive: true })
  writeFileSync(logPath, '', 'utf8')

  writeSiteOpStatus(domain, op, 'running', message)
}

export function systemUpdateLogPath(): string {
  return join(stackRoot(), 'logs', 'panel', 'dpanel-update.log')
}

export function systemUpdateStatusPath(): string {
  return join(stackRoot(), 'data', 'panel', 'system-update.json')
}

export function systemUpdateLockPath(): string {
  return join(stackRoot(), 'data', 'panel', '.update-lock')
}

/** True if a panel/system update process (or its docker runner) looks alive. */
export function isSystemUpdateProcessAlive(): boolean {
  try {
    const r = spawnSync(
      'bash',
      [
        '-lc',
        [
          "pgrep -af 'panel-update\\.sh' >/dev/null 2>&1",
          "|| pgrep -af 'panel-update-host' >/dev/null 2>&1",
          "|| pgrep -af 'infra/scripts/update\\.sh' >/dev/null 2>&1",
          // docker run alpine … panel-update-host (compose build can take a long time)
          "|| docker ps --format '{{.Command}}' 2>/dev/null | grep -q 'panel-update-host'"
        ].join(' ')
      ],
      { timeout: 8000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

/**
 * Force-restart a UI-triggered dpanel update: kill any in-flight job, drop lock, clear log.
 */
export function beginSystemUpdate(message: string): void {
  spawnSync(
    'bash',
    [
      '-lc',
      [
        "pkill -9 -f 'infra/scripts/panel-update\\.sh' 2>/dev/null || true",
        "pkill -9 -f 'infra/scripts/panel-update-host\\.sh' 2>/dev/null || true",
        "pkill -9 -f 'infra/scripts/update\\.sh' 2>/dev/null || true",
        // Alpine chroot runner from panel-update.sh
        `for id in $(docker ps -q 2>/dev/null); do
           cmd=$(docker inspect -f '{{json .Config.Cmd}}' "$id" 2>/dev/null || true)
           echo "$cmd" | grep -q 'panel-update-host' && docker kill "$id" 2>/dev/null || true
         done`,
        'sleep 0.3'
      ].join('; ')
    ],
    { timeout: 20_000, encoding: 'utf8' }
  )

  try {
    rmSync(systemUpdateLockPath(), { recursive: true, force: true })
  } catch {
    /* ignore */
  }

  // Create lock immediately so status polls don't treat the spawn gap as "stuck".
  try {
    mkdirSync(systemUpdateLockPath())
  } catch {
    /* race with panel-update.sh — fine */
  }

  const logPath = systemUpdateLogPath()
  mkdirSync(dirname(logPath), { recursive: true })
  writeFileSync(logPath, '', 'utf8')
  writeSystemUpdateStatus('running', message)
}

export function writeSystemUpdateStatus(
  status: 'running' | 'ok' | 'error',
  message = ''
): void {
  const dir = join(stackRoot(), 'data', 'panel')
  mkdirSync(dir, { recursive: true })
  const path = systemUpdateStatusPath()
  writeFileSync(
    path,
    JSON.stringify(
      {
        op: 'update',
        status,
        message,
        updatedAt: new Date().toISOString()
      },
      null,
      2
    ),
    'utf8'
  )
}

export function writeSiteOpStatus(
  domain: string,
  op: SiteOpKind,
  status: 'running' | 'ok' | 'error',
  message = ''
): void {
  const dir = join(stackRoot(), 'data', 'panel', 'site-ops')
  mkdirSync(dir, { recursive: true })
  const path = join(dir, `${domain}.json`)
  writeFileSync(
    path,
    JSON.stringify(
      {
        domain,
        op,
        status,
        message,
        updatedAt: new Date().toISOString()
      },
      null,
      2
    ),
    'utf8'
  )
}

export function siteOpStatusPath(domain: string): string {
  return join(stackRoot(), 'data', 'panel', 'site-ops', `${domain}.json`)
}

export function siteOpsLockPath(): string {
  return join(stackRoot(), 'data', 'panel', '.site-ops.lock')
}

/** True if update/rebuild for this domain looks alive. */
export function isSiteOpProcessAlive(domain: string, op?: SiteOpKind): boolean {
  const safeDomain = domain.replace(/[^a-zA-Z0-9.-]/g, '')
  if (!safeDomain) return false
  const script =
    op === 'update'
      ? `site-update\\.sh ${safeDomain}`
      : op === 'rebuild'
        ? `site-rebuild\\.sh ${safeDomain}`
        : `site-(update|rebuild)\\.sh ${safeDomain}`
  try {
    const r = spawnSync(
      'bash',
      ['-lc', `pgrep -af '${script}' >/dev/null 2>&1`],
      { timeout: 8000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

/** True if any site-update / site-rebuild script is running (any domain). */
export function isAnySiteOpProcessAlive(): boolean {
  try {
    const r = spawnSync(
      'bash',
      ['-lc', "pgrep -af 'site-(update|rebuild)\\.sh ' >/dev/null 2>&1"],
      { timeout: 8000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

export type ClearStuckJobsResult = {
  ok: true
  killedProcesses: boolean
  clearedUpdateLock: boolean
  clearedSiteOpsLock: boolean
  clearedSystemUpdateStatus: boolean
  clearedSiteOps: number
  clearedLogs: number
}

/**
 * Kill hung Update Dpanel / Update website / Rebuild jobs, drop locks,
 * mark running statuses as error, and truncate related logs.
 */
export function clearStuckJobs(): ClearStuckJobsResult {
  spawnSync(
    'bash',
    [
      '-lc',
      [
        "pkill -9 -f 'site-rebuild\\.sh' 2>/dev/null || true",
        "pkill -9 -f 'site-update\\.sh' 2>/dev/null || true",
        "pkill -9 -f 'infra/scripts/panel-update\\.sh' 2>/dev/null || true",
        "pkill -9 -f 'infra/scripts/panel-update-host\\.sh' 2>/dev/null || true",
        "pkill -9 -f 'infra/scripts/update\\.sh' 2>/dev/null || true",
        `for id in $(docker ps -q 2>/dev/null); do
           cmd=$(docker inspect -f '{{json .Config.Cmd}}' "$id" 2>/dev/null || true)
           echo "$cmd" | grep -q 'panel-update-host' && docker kill "$id" 2>/dev/null || true
         done`,
        'sleep 0.2'
      ].join('; ')
    ],
    { timeout: 20_000, encoding: 'utf8' }
  )

  let clearedUpdateLock = false
  let clearedSiteOpsLock = false
  try {
    rmSync(systemUpdateLockPath(), { recursive: true, force: true })
    clearedUpdateLock = true
  } catch {
    /* ignore */
  }
  try {
    rmSync(siteOpsLockPath(), { recursive: true, force: true })
    clearedSiteOpsLock = true
  } catch {
    /* ignore */
  }

  let clearedSystemUpdateStatus = false
  try {
    const path = systemUpdateStatusPath()
    if (existsSync(path)) {
      const raw = JSON.parse(readFileSync(path, 'utf8')) as { status?: string }
      if (raw.status === 'running') {
        writeSystemUpdateStatus('error', 'Cleared stuck update (Clean Job)')
        clearedSystemUpdateStatus = true
      }
    }
  } catch {
    /* ignore */
  }

  let clearedSiteOps = 0
  const siteOpsDir = join(stackRoot(), 'data', 'panel', 'site-ops')
  try {
    if (existsSync(siteOpsDir)) {
      for (const name of readdirSync(siteOpsDir)) {
        if (!name.endsWith('.json')) continue
        const path = join(siteOpsDir, name)
        try {
          const data = JSON.parse(readFileSync(path, 'utf8')) as {
            domain?: string
            op?: string
            status?: string
          }
          if (data.status !== 'running') continue
          const domain = (data.domain || name.replace(/\.json$/, '')).trim().toLowerCase()
          const op: SiteOpKind =
            data.op === 'update' || data.op === 'rebuild' ? data.op : 'rebuild'
          writeSiteOpStatus(domain, op, 'error', 'Cleared stuck job (Clean Job)')
          clearedSiteOps += 1
        } catch {
          /* ignore one file */
        }
      }
    }
  } catch {
    /* ignore */
  }

  let clearedLogs = 0
  const truncateLog = (path: string) => {
    try {
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, '', 'utf8')
      clearedLogs += 1
    } catch {
      /* ignore */
    }
  }
  truncateLog(systemUpdateLogPath())

  const nodeLogs = join(stackRoot(), 'logs', 'node')
  try {
    if (existsSync(nodeLogs)) {
      for (const name of readdirSync(nodeLogs)) {
        if (
          name.startsWith('site-update-') ||
          name.startsWith('site-rebuild-') ||
          name.startsWith('site-create-')
        ) {
          truncateLog(join(nodeLogs, name))
        }
      }
    }
  } catch {
    /* ignore */
  }

  return {
    ok: true,
    killedProcesses: true,
    clearedUpdateLock,
    clearedSiteOpsLock,
    clearedSystemUpdateStatus,
    clearedSiteOps,
    clearedLogs
  }
}

/** Start a bash script in the background (panel API returns immediately — no 502 from long work). */
export function runScriptDetached(
  script: string,
  args: string[] = [],
  extraEnv: Record<string, string> = {},
  logDomain?: string,
  logOp?: string
): void {
  let stdio: 'ignore' | ['ignore', number, number] = 'ignore'
  if (logDomain && logOp) {
    const logPath = join(stackRoot(), 'logs/node', siteLogBasename(logDomain, logOp))
    mkdirSync(dirname(logPath), { recursive: true })
    const fd = openSync(logPath, 'a')
    stdio = ['ignore', fd, fd]
  }
  const child = spawn('bash', [scriptPath(script), ...args], {
    cwd: stackRoot(),
    env: { ...process.env, STACK_ROOT: stackRoot(), ...extraEnv },
    detached: true,
    stdio
  })
  child.unref()
}

export async function runScript(
  script: string,
  args: string[] = [],
  timeoutMs = 120_000,
  extraEnv: Record<string, string> = {}
): Promise<string> {
  try {
    const { stdout, stderr } = await execFileAsync('bash', [scriptPath(script), ...args], {
      env: { ...process.env, STACK_ROOT: stackRoot(), ...extraEnv },
      timeout: timeoutMs,
      maxBuffer: 4 * 1024 * 1024
    })
    const out = (stdout || '').trim()
    const err = (stderr || '').trim()
    if (out) return out
    if (err) return err
    return ''
  } catch (e: unknown) {
    throw new Error(scriptErrorMessage(e))
  }
}

/** Parse last JSON object line from bash script stdout (ignores log lines). */
export function parseScriptJson<T extends Record<string, unknown>>(stdout: string): T {
  const lines = stdout
    .trim()
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('{'))
  const last = lines[lines.length - 1]
  if (!last) {
    throw new Error('Script did not return JSON')
  }
  return JSON.parse(last) as T
}

export function authFilePath(): string {
  return join(stackRoot(), 'data', 'panel', 'auth.json')
}

export async function readAuth() {
  const raw = await readFile(authFilePath(), 'utf8')
  return JSON.parse(raw) as { email: string; passwordHash: string }
}

export async function updateAuthPassword(passwordHash: string): Promise<void> {
  const auth = await readAuth()
  const path = authFilePath()
  await writeFile(path, JSON.stringify({ ...auth, passwordHash }), 'utf8')
  try {
    chmodSync(path, 0o600)
  } catch {
    /* ignore when path is not writable (local dev) */
  }
}
