import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { requireAuth } from '../../utils/auth-guard'
import { listApiKeys } from '../../utils/api-keys'
import { stackRoot } from '../../utils/stack'
import type { SiteRecord } from '../../utils/sites'

export type DashboardSummary = {
  nodeSites: number
  phpSites: number
  databases: number
  apiKeys: number
}

async function readJsonArray<T>(path: string): Promise<T[]> {
  try {
    const raw = JSON.parse(await readFile(path, 'utf8')) as unknown
    return Array.isArray(raw) ? (raw as T[]) : []
  } catch {
    return []
  }
}

/** Fast counts from panel JSON only — no docker exec / MariaDB. */
export default defineEventHandler(async (event): Promise<DashboardSummary> => {
  requireAuth(event)

  const panelDir = join(stackRoot(), 'data', 'panel')
  const [sites, databases, keys] = await Promise.all([
    readJsonArray<SiteRecord>(join(panelDir, 'sites.json')),
    readJsonArray<{ name?: string }>(join(panelDir, 'databases.json')),
    listApiKeys()
  ])

  let nodeSites = 0
  let phpSites = 0
  for (const s of sites) {
    if (s.runtime === 'node') nodeSites++
    else if (s.runtime === 'php') phpSites++
  }

  return {
    nodeSites,
    phpSites,
    databases: databases.filter((d) => (d?.name || '').trim()).length,
    apiKeys: keys.length
  }
})
