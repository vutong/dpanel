import { stat } from 'node:fs/promises'
import { join } from 'node:path'
import { requireAuth } from '../../utils/auth-guard'
import { panelDataDir, readSitesJson } from '../../utils/cache-store'
import { withPendingMeta, type SiteRecord } from '../../utils/sites'

export default defineEventHandler(async () => {
  requireAuth(event)

  const sitesPath = join(panelDataDir(), 'sites.json')
  const raw = await readSitesJson<SiteRecord[]>()
  if (raw === null) {
    throw createError({ statusCode: 500, statusMessage: 'sites.json not found or invalid' })
  }

  let ageSec = 0
  try {
    const st = await stat(sitesPath)
    ageSec = Math.max(0, Math.floor((Date.now() - st.mtimeMs) / 1000))
  } catch {
    /* ignore */
  }

  const sites = (Array.isArray(raw) ? raw : []).map((s) => withPendingMeta(s))
  return {
    sites,
    _cache: {
      ageSec,
      stale: false,
      warming: false
    }
  }
})
