import { execFile, spawn, spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync, openSync, rmdirSync, rmSync, writeFileSync } from 'node:fs'
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
 * Clear any stuck prior run (log + lock + status) before starting update/rebuild.
 * Avoids the stream modal hanging on a stale `running` / leftover `{"ok":false}` log.
 */
export function beginSiteOp(domain: string, op: SiteOpKind, message: string): void {
  const logPath = siteOpLogPath(domain, op)
  mkdirSync(dirname(logPath), { recursive: true })
  writeFileSync(logPath, '', 'utf8')

  // Stale lock from a killed rebuild can block the next build for minutes.
  try {
    rmdirSync(join(stackRoot(), 'data', 'panel', '.site-ops.lock'))
  } catch {
    /* not held or not empty — ignore */
  }

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

/** True if an update.sh / panel-update-host process is alive on the host. */
export function isSystemUpdateProcessAlive(): boolean {
  try {
    const r = spawnSync(
      'bash',
      [
        '-lc',
        "pgrep -af 'infra/scripts/(update\\.sh|panel-update-host\\.sh|panel-update\\.sh)' >/dev/null 2>&1"
      ],
      { timeout: 5000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

/**
 * Prepare a fresh UI-triggered update: clear stale lock/log, mark running.
 * If a real update is already in progress, returns alreadyRunning without wiping the log.
 */
export function beginSystemUpdate(message: string): { alreadyRunning: boolean } {
  const alive = isSystemUpdateProcessAlive()
  const lockPath = systemUpdateLockPath()

  if (alive) {
    writeSystemUpdateStatus('running', message || 'Update already in progress…')
    return { alreadyRunning: true }
  }

  // Stale lock from a killed/crashed update blocks every later click.
  try {
    rmdirSync(lockPath)
  } catch {
    try {
      rmSync(lockPath, { recursive: true, force: true })
    } catch {
      /* ignore */
    }
  }

  const logPath = systemUpdateLogPath()
  mkdirSync(dirname(logPath), { recursive: true })
  writeFileSync(logPath, '', 'utf8')
  writeSystemUpdateStatus('running', message)
  return { alreadyRunning: false }
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
