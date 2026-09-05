/**
 * Dev inline collector when DPANEL_COLLECTOR=inline or inline-full (no compose cache-collector).
 * Production uses infra/scripts/cache-collector-loop.sh as a separate Docker service.
 */
import { spawn } from 'node:child_process'
import { join } from 'node:path'
import { writeCacheAtomic } from '../utils/cache-store'
import { stackRoot } from '../utils/stack'

const COLLECTOR_MODE = process.env.DPANEL_COLLECTOR || ''
const STATS_INTERVAL_MS = Number(process.env.DPANEL_CACHE_STATS_INTERVAL_ACTIVE_MS || 8000)
const SECURITY_INTERVAL_MS = Number(process.env.DPANEL_CACHE_SECURITY_INTERVAL_ACTIVE_MS || 60_000)

function scriptsDir(): string {
  return join(stackRoot(), 'infra', 'scripts')
}

function lastJsonLine(stdout: string): string {
  const lines = stdout
    .trim()
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.startsWith('{') || l.startsWith('['))
  return lines[lines.length - 1] || ''
}

function runScriptCapture(script: string, args: string[] = []): Promise<string> {
  return new Promise((resolve) => {
    const child = spawn('bash', [join(scriptsDir(), script), ...args], {
      env: { ...process.env, STACK_ROOT: stackRoot() },
      stdio: ['ignore', 'pipe', 'pipe']
    })
    let stdout = ''
    child.stdout?.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf8')
    })
    child.on('close', () => resolve(stdout))
  })
}

async function writeFromScriptJson(
  cacheName: string,
  script: string,
  args: string[],
  staleAfterSec: number,
  pickArray = false
): Promise<void> {
  const stdout = await runScriptCapture(script, args)
  const line = lastJsonLine(stdout)
  if (!line) return
  if (pickArray && !line.startsWith('[')) return
  if (!pickArray && !line.startsWith('{')) return
  try {
    const data = JSON.parse(line) as unknown
    await writeCacheAtomic(cacheName, {
      ok: true,
      updatedAt: new Date().toISOString(),
      staleAfterSec,
      warming: false,
      data
    })
  } catch {
    /* ignore */
  }
}

async function runStatsJob(): Promise<void> {
  await writeFromScriptJson('stats.json', 'docker-stats.sh', [], 15)
}

async function runSecurityJob(): Promise<void> {
  const [statusOut, f2bOut, clamOut] = await Promise.all([
    runScriptCapture('host-security-status.sh'),
    runScriptCapture('host-fail2ban-query.sh', ['summary']),
    runScriptCapture('host-clamav-query.sh', ['summary'])
  ])
  const statusLine = lastJsonLine(statusOut)
  const f2bLine = lastJsonLine(f2bOut)
  const clamLine = lastJsonLine(clamOut)
  if (!statusLine && !f2bLine && !clamLine) return
  try {
    const combined: Record<string, unknown> = {}
    if (statusLine) combined.status = JSON.parse(statusLine)
    if (f2bLine) combined.fail2banSummary = JSON.parse(f2bLine)
    if (clamLine) combined.clamavSummary = JSON.parse(clamLine)
    await writeCacheAtomic('security.json', {
      ok: true,
      updatedAt: new Date().toISOString(),
      staleAfterSec: 90,
      warming: false,
      data: combined
    })
  } catch {
    /* ignore */
  }
}

export default defineNitroPlugin(() => {
  if (COLLECTOR_MODE !== 'inline' && COLLECTOR_MODE !== 'inline-full') return

  void runStatsJob()
  const statsTimer = setInterval(() => void runStatsJob(), STATS_INTERVAL_MS)
  statsTimer.unref?.()

  if (COLLECTOR_MODE === 'inline-full') {
    void runSecurityJob()
    const securityTimer = setInterval(() => void runSecurityJob(), SECURITY_INTERVAL_MS)
    securityTimer.unref?.()
  }
})
