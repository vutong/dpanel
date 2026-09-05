import { requireAuth } from '../../utils/auth-guard'
import {
  isCollectorPaused,
  readCollectorState,
  reconcileOpRunning
} from '../../utils/cache-meta'
import { readCache, cacheFilePath } from '../../utils/cache-store'
import { stat } from 'node:fs/promises'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const meta = await reconcileOpRunning()
  const collectorState = await readCollectorState()

  async function fileAgeSec(name: string): Promise<number | null> {
    try {
      const st = await stat(cacheFilePath(name))
      return Math.max(0, Math.floor((Date.now() - st.mtimeMs) / 1000))
    } catch {
      return null
    }
  }

  const statsCache = await readCache('stats.json')

  return {
    ok: true,
    opRunning: meta.opRunning,
    opRunningSince: meta.opRunningSince,
    collectorPaused: isCollectorPaused(meta),
    diskTestActive: Boolean(meta.diskTestActive),
    pendingForce: meta.pendingForce,
    collectorLastRun: collectorState.collectorLastRun,
    statsAgeSec: statsCache.ageSec,
    statsStale: statsCache.isStale,
    statsFileAgeSec: await fileAgeSec('stats.json')
  }
})
