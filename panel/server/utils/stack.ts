import { execFile, spawn } from 'node:child_process'
import { mkdirSync, openSync, writeFileSync } from 'node:fs'
import { promisify } from 'node:util'
import { readFile } from 'node:fs/promises'
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

/** Reset site-ops status before a background script starts (avoids stale poll results). */
export type SystemUpdateStatus = {
  op?: 'update'
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
  updatedAt?: string
}

export function systemUpdateLogPath(): string {
  return join(stackRoot(), 'logs', 'panel', 'dpanel-update.log')
}

export function systemUpdateStatusPath(): string {
  return join(stackRoot(), 'data', 'panel', 'system-update.json')
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

export async function readAuth() {
  const raw = await readFile(join(stackRoot(), 'data', 'panel', 'auth.json'), 'utf8')
  return JSON.parse(raw) as { email: string; passwordHash: string }
}
