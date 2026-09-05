import { requireAuth } from '../../../utils/auth-guard'
import {
  isSystemUpdateProcessAlive,
  systemUpdateLockPath,
  systemUpdateStatusPath,
  writeSystemUpdateStatus,
  type SystemUpdateStatus
} from '../../../utils/stack'
import { readMicroCache, writeMicroCache } from '../../../utils/cache-store'
import { readFile } from 'node:fs/promises'
import { rmSync } from 'node:fs'

/** Grace before treating a "running" update with no visible process as stuck. */
const STUCK_GRACE_MS = 3 * 60_000
const MICRO_CACHE_MS = 2000
const CACHE_KEY = 'system-update-op'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const cached = readMicroCache<SystemUpdateStatus>(CACHE_KEY, MICRO_CACHE_MS)
  if (cached) {
    return cached
  }

  let status: SystemUpdateStatus
  try {
    const raw = await readFile(systemUpdateStatusPath(), 'utf8')
    status = JSON.parse(raw) as SystemUpdateStatus
  } catch {
    const none = { op: 'update', status: 'none' as const } satisfies SystemUpdateStatus
    writeMicroCache(CACHE_KEY, none)
    return none
  }

  if (status.status !== 'running') {
    writeMicroCache(CACHE_KEY, status)
    return status
  }

  // Process alive (script or alpine host runner) ⇒ still working.
  if (await isSystemUpdateProcessAlive()) {
    writeMicroCache(CACHE_KEY, status)
    return status
  }

  const updatedAtMs = status.updatedAt ? Date.parse(status.updatedAt) : 0
  const ageMs = Date.now() - (Number.isNaN(updatedAtMs) ? 0 : updatedAtMs)

  // Fresh click: beginSystemUpdate writes running before spawn — do not error immediately.
  // Do NOT treat .update-lock alone as liveness: SIGKILL/OOM can orphan the lock forever.
  if (ageMs < STUCK_GRACE_MS) {
    writeMicroCache(CACHE_KEY, status)
    return status
  }

  try {
    rmSync(systemUpdateLockPath(), { recursive: true, force: true })
  } catch {
    /* ignore */
  }
  const message =
    'Update was interrupted or stuck (no process running). Click Update Dpanel to try again.'
  writeSystemUpdateStatus('error', message)
  const result = {
    op: 'update' as const,
    status: 'error' as const,
    message,
    updatedAt: new Date().toISOString()
  }
  writeMicroCache(CACHE_KEY, result)
  return result
})
