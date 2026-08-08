import { requireAuth } from '../../../utils/auth-guard'
import {
  isSystemUpdateProcessAlive,
  systemUpdateLockPath,
  systemUpdateStatusPath,
  writeSystemUpdateStatus,
  type SystemUpdateStatus
} from '../../../utils/stack'
import { access, readFile } from 'node:fs/promises'
import { rmdirSync, rmSync } from 'node:fs'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  let status: SystemUpdateStatus
  try {
    const raw = await readFile(systemUpdateStatusPath(), 'utf8')
    status = JSON.parse(raw) as SystemUpdateStatus
  } catch {
    return { op: 'update', status: 'none' as const } satisfies SystemUpdateStatus
  }

  // Heal stuck "running" when nothing is actually updating (stale lock / crashed job).
  if (status.status === 'running' && !isSystemUpdateProcessAlive()) {
    let lockPresent = false
    try {
      await access(systemUpdateLockPath())
      lockPresent = true
    } catch {
      lockPresent = false
    }

    const updatedAtMs = status.updatedAt ? Date.parse(status.updatedAt) : 0
    const ageMs = Date.now() - (Number.isNaN(updatedAtMs) ? 0 : updatedAtMs)
    // Give a fresh start a few seconds; after that treat as stuck.
    if (!lockPresent || ageMs > 15_000) {
      try {
        rmdirSync(systemUpdateLockPath())
      } catch {
        try {
          rmSync(systemUpdateLockPath(), { recursive: true, force: true })
        } catch {
          /* ignore */
        }
      }
      writeSystemUpdateStatus(
        'error',
        'Update was interrupted or stuck (no process running). Click Update Dpanel to try again.'
      )
      return {
        op: 'update' as const,
        status: 'error' as const,
        message:
          'Update was interrupted or stuck (no process running). Click Update Dpanel to try again.',
        updatedAt: new Date().toISOString()
      }
    }
  }

  return status
})
