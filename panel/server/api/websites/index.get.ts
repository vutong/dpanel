import { requireAuth } from '../../utils/auth-guard'
import { runScript, runScriptDetached } from '../../utils/stack'
import { withPendingMeta, type SiteRecord } from '../../utils/sites'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  // Best-effort: purge soft-deleted sites past 24h (no cron required).
  runScriptDetached('site-purge-expired.sh', [])

  const raw = await runScript('site-list.sh')
  const sites = JSON.parse(raw || '[]') as SiteRecord[]
  const list = (Array.isArray(sites) ? sites : []).map((s) => withPendingMeta(s))
  return { sites: list }
})
