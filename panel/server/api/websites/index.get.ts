import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { requireAuth } from '../../utils/auth-guard'
import { runScript, runScriptDetached, stackRoot } from '../../utils/stack'
import { withPendingMeta, type SiteRecord } from '../../utils/sites'

/** Avoid spawning purge on every websites list (dashboard / nav traffic). */
const PURGE_MIN_INTERVAL_MS = 15 * 60 * 1000

function maybePurgeExpiredSites() {
  const stampPath = join(stackRoot(), 'data', 'panel', '.site-purge-stamp')
  try {
    if (existsSync(stampPath)) {
      const last = Number(String(readFileSync(stampPath, 'utf8')).trim())
      if (Number.isFinite(last) && Date.now() - last < PURGE_MIN_INTERVAL_MS) return
    }
  } catch {
    /* ignore */
  }
  try {
    mkdirSync(dirname(stampPath), { recursive: true })
    writeFileSync(stampPath, String(Date.now()), 'utf8')
  } catch {
    /* ignore */
  }
  runScriptDetached('site-purge-expired.sh', [])
}

export default defineEventHandler(async (event) => {
  requireAuth(event)

  // Best-effort: purge soft-deleted sites past 24h (no cron required).
  maybePurgeExpiredSites()

  const raw = await runScript('site-list.sh')
  const sites = JSON.parse(raw || '[]') as SiteRecord[]
  const list = (Array.isArray(sites) ? sites : []).map((s) => withPendingMeta(s))
  return { sites: list }
})
