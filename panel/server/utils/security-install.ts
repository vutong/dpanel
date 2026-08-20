import { spawn, spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, openSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { appendSecurityEvent } from './security-events'
import { scriptPath, stackRoot } from './stack'

export type SecurityInstallOp = 'fail2ban' | 'clamav'

export type SecurityInstallStatus = {
  op: SecurityInstallOp
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
  updatedAt?: string
  eventRecorded?: boolean
}

const STUCK_GRACE_MS: Record<SecurityInstallOp, number> = {
  fail2ban: 10 * 60_000,
  clamav: 25 * 60_000
}

export function securityInstallStatusPath(op: SecurityInstallOp): string {
  return join(stackRoot(), 'data', 'panel', `security-install-${op}.json`)
}

export function securityInstallLogPath(op: SecurityInstallOp): string {
  return join(stackRoot(), 'logs', 'panel', `security-install-${op}.log`)
}

export function readSecurityInstallStatus(op: SecurityInstallOp): SecurityInstallStatus {
  try {
    const raw = readFileSync(securityInstallStatusPath(op), 'utf8')
    return JSON.parse(raw) as SecurityInstallStatus
  } catch {
    return { op, status: 'none' }
  }
}

export function writeSecurityInstallStatus(
  op: SecurityInstallOp,
  status: Exclude<SecurityInstallStatus['status'], 'none'>,
  message = '',
  eventRecorded?: boolean
): void {
  const dir = join(stackRoot(), 'data', 'panel')
  mkdirSync(dir, { recursive: true })
  const prev = readSecurityInstallStatus(op)
  writeFileSync(
    securityInstallStatusPath(op),
    JSON.stringify(
      {
        op,
        status,
        message,
        updatedAt: new Date().toISOString(),
        eventRecorded: eventRecorded ?? prev.eventRecorded ?? false
      },
      null,
      2
    ) + '\n',
    'utf8'
  )
}

export function isSecurityInstallProcessAlive(op: SecurityInstallOp): boolean {
  const safeOp = op.replace(/[^a-z]/g, '')
  const patterns = [
    `host-security-install-bg\\.sh ${safeOp}`,
    op === 'fail2ban' ? 'host-fail2ban-install\\.sh' : 'host-clamav-install\\.sh'
  ]
  try {
    const r = spawnSync(
      'bash',
      ['-lc', patterns.map((p) => `pgrep -af '${p}' >/dev/null 2>&1`).join(' || ')],
      { timeout: 8000, encoding: 'utf8' }
    )
    return r.status === 0
  } catch {
    return false
  }
}

/** Mark stuck background installs as error when no process is running. */
export function resolveSecurityInstallStatus(op: SecurityInstallOp): SecurityInstallStatus {
  const status = readSecurityInstallStatus(op)
  if (status.status !== 'running') {
    return status
  }

  if (isSecurityInstallProcessAlive(op)) {
    return status
  }

  const updatedAtMs = status.updatedAt ? Date.parse(status.updatedAt) : 0
  const ageMs = Date.now() - (Number.isNaN(updatedAtMs) ? 0 : updatedAtMs)
  if (ageMs < STUCK_GRACE_MS[op]) {
    return status
  }

  const message =
    status.message ||
    'Install was interrupted or timed out. Check the log and try again.'
  writeSecurityInstallStatus(op, 'error', message)
  return {
    op,
    status: 'error',
    message,
    updatedAt: new Date().toISOString(),
    eventRecorded: status.eventRecorded
  }
}

export function beginSecurityInstall(op: SecurityInstallOp, message: string): boolean {
  const current = resolveSecurityInstallStatus(op)
  if (current.status === 'running' && isSecurityInstallProcessAlive(op)) {
    return false
  }

  spawnSync(
    'bash',
    [
      '-lc',
      [
        op === 'fail2ban'
          ? "pkill -9 -f 'host-fail2ban-install\\.sh' 2>/dev/null || true"
          : "pkill -9 -f 'host-clamav-install\\.sh' 2>/dev/null || true",
        `pkill -9 -f 'host-security-install-bg\\.sh ${op}' 2>/dev/null || true`,
        'sleep 0.2'
      ].join('; ')
    ],
    { timeout: 12_000, encoding: 'utf8' }
  )

  const logPath = securityInstallLogPath(op)
  mkdirSync(dirname(logPath), { recursive: true })
  writeFileSync(logPath, '', 'utf8')
  writeSecurityInstallStatus(op, 'running', message, false)
  return true
}

export function startSecurityInstallDetached(op: SecurityInstallOp): void {
  const logPath = securityInstallLogPath(op)
  mkdirSync(dirname(logPath), { recursive: true })
  const fd = openSync(logPath, 'a')
  const child = spawn('bash', [scriptPath('host-security-install-bg.sh'), op], {
    cwd: stackRoot(),
    env: { ...process.env, STACK_ROOT: stackRoot() },
    detached: true,
    stdio: ['ignore', fd, fd]
  })
  child.unref()
}

export function recordSecurityInstallEventIfNeeded(op: SecurityInstallOp): SecurityInstallStatus {
  const status = resolveSecurityInstallStatus(op)
  if (status.status !== 'ok' || status.eventRecorded) {
    return status
  }

  appendSecurityEvent({
    kind: 'security_install',
    source: 'panel',
    action: 'installed',
    detail: op === 'fail2ban' ? 'Fail2ban installed from panel' : 'ClamAV installed from panel'
  })
  writeSecurityInstallStatus(op, 'ok', status.message || 'Installed', true)
  return { ...status, eventRecorded: true }
}

export function startSecurityInstall(op: SecurityInstallOp): {
  ok: true
  accepted: boolean
  background: true
  op: SecurityInstallOp
  status: SecurityInstallStatus['status']
  message?: string
} {
  const label = op === 'fail2ban' ? 'Fail2ban' : 'ClamAV'
  const started = beginSecurityInstall(op, `Installing ${label}…`)
  if (!started) {
    const current = resolveSecurityInstallStatus(op)
    return {
      ok: true,
      accepted: false,
      background: true,
      op,
      status: current.status,
      message: current.message
    }
  }

  startSecurityInstallDetached(op)
  return {
    ok: true,
    accepted: true,
    background: true,
    op,
    status: 'running',
    message: `Installing ${label}…`
  }
}

export function securityInstallIsRunning(op: SecurityInstallOp): boolean {
  return resolveSecurityInstallStatus(op).status === 'running'
}

export function clearSecurityInstallStatus(op: SecurityInstallOp): void {
  try {
    rmSync(securityInstallStatusPath(op), { force: true })
  } catch {
    /* ignore */
  }
}

export function securityInstallLogExists(op: SecurityInstallOp): boolean {
  return existsSync(securityInstallLogPath(op))
}
