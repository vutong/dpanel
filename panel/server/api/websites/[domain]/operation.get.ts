import { requireAuth } from '../../../utils/auth-guard'
import {
  isAnySiteOpProcessAlive,
  isSiteOpProcessAlive,
  siteOpsLockPath,
  siteOpStatusPath,
  writeSiteOpStatus,
  type SiteOpKind
} from '../../../utils/stack'
import { readMicroCache, writeMicroCache } from '../../../utils/cache-store'
import { readFile } from 'node:fs/promises'
import { rmSync } from 'node:fs'

export type SiteOperationStatus = {
  domain?: string
  op?: string
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
  updatedAt?: string
}

/** Grace before treating a "running" site op with no visible process as stuck. */
const STUCK_GRACE_MS = 2 * 60_000
const MICRO_CACHE_MS = 2000

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const cacheKey = `site-op:${domain}`
  const cached = readMicroCache<SiteOperationStatus>(cacheKey, MICRO_CACHE_MS)
  if (cached) {
    return cached
  }

  const path = siteOpStatusPath(domain)
  let status: SiteOperationStatus
  try {
    const raw = await readFile(path, 'utf8')
    status = JSON.parse(raw) as SiteOperationStatus
  } catch {
    const none = { domain, status: 'none' as const }
    writeMicroCache(cacheKey, none)
    return none
  }

  if (status.status !== 'running') {
    writeMicroCache(cacheKey, status)
    return status
  }

  const op = (
    status.op === 'update' || status.op === 'rebuild' || status.op === 'fix-permissions'
      ? status.op
      : undefined
  ) as SiteOpKind | undefined

  // This domain's update/rebuild process is alive ⇒ still working.
  if (await isSiteOpProcessAlive(domain, op)) {
    writeMicroCache(cacheKey, status)
    return status
  }

  const updatedAtMs = status.updatedAt ? Date.parse(status.updatedAt) : 0
  const ageMs = Date.now() - (Number.isNaN(updatedAtMs) ? 0 : updatedAtMs)

  // Fresh start / brief pgrep gap — wait. Do NOT treat global .site-ops.lock as liveness:
  // another site may hold it, or SIGKILL can orphan it while this domain's job is dead.
  if (ageMs < STUCK_GRACE_MS) {
    writeMicroCache(cacheKey, status)
    return status
  }

  // Only clear the global lock when no site-op script is running anywhere.
  if (!(await isAnySiteOpProcessAlive())) {
    try {
      rmSync(siteOpsLockPath(), { recursive: true, force: true })
    } catch {
      /* ignore */
    }
  }

  const message =
    'Operation was interrupted or stuck (no process running). Retry Rebuild or Update from Git.'
  const stuckOp: SiteOpKind = op || 'rebuild'
  writeSiteOpStatus(domain, stuckOp, 'error', message)
  const result = {
    domain,
    op: stuckOp,
    status: 'error' as const,
    message,
    updatedAt: new Date().toISOString()
  }
  writeMicroCache(cacheKey, result)
  return result
})
