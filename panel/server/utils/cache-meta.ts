import { readFile, rename, writeFile } from 'node:fs/promises'

import { join } from 'node:path'

import { cacheRootDir, ensureCacheDir } from './cache-store'



export type CacheSectionKey = 'dashboard' | 'databases' | 'websites' | 'settings'



export type CacheSectionState = {

  lastSeenAt: string

  domain?: string

}



/** Panel-owned cache coordination (presence, ops, force refresh). */

export type CacheMeta = {

  sections: Partial<Record<CacheSectionKey, CacheSectionState>>

  opRunning: boolean

  opRunningSince: string | null

  pausedUntil: string | null

  pendingForce: string[]

  diskTestActive?: boolean

}



/** Collector-owned job timestamps — separate file to avoid write races with panel meta. */
export type CollectorState = {
  collectorLastRun: Partial<Record<string, string>>
  siteResourcesCursor?: number
}



const META_NAME = 'meta.json'

const COLLECTOR_STATE_NAME = 'collector-state.json'



const OP_RUNNING_GRACE_MS = 2 * 60_000



export function opRunningMaxMs(): number {

  return Number(process.env.DPANEL_OP_RUNNING_MAX_MS || 30 * 60_000)

}



export function defaultCacheMeta(): CacheMeta {

  return {

    sections: {},

    opRunning: false,

    opRunningSince: null,

    pausedUntil: null,

    pendingForce: []

  }

}



export function defaultCollectorState(): CollectorState {

  return { collectorLastRun: {} }

}



export function metaFilePath(): string {

  return join(cacheRootDir(), META_NAME)

}



export function collectorStateFilePath(): string {

  return join(cacheRootDir(), COLLECTOR_STATE_NAME)

}



function parsePanelMeta(parsed: Record<string, unknown>): CacheMeta {

  const base = defaultCacheMeta()

  const sections = (parsed.sections as CacheMeta['sections']) || {}

  return {

    sections: { ...base.sections, ...sections },

    opRunning: Boolean(parsed.opRunning),

    opRunningSince:

      typeof parsed.opRunningSince === 'string'

        ? parsed.opRunningSince

        : parsed.opRunning

          ? null

          : null,

    pausedUntil: typeof parsed.pausedUntil === 'string' ? parsed.pausedUntil : null,

    pendingForce: Array.isArray(parsed.pendingForce)

      ? parsed.pendingForce.map(String)

      : base.pendingForce,

    diskTestActive: parsed.diskTestActive ? true : undefined

  }

}



export async function readCollectorState(): Promise<CollectorState> {

  try {

    const raw = await readFile(collectorStateFilePath(), 'utf8')

    const parsed = JSON.parse(raw) as Partial<CollectorState>

    return {

      collectorLastRun: {

        ...defaultCollectorState().collectorLastRun,

        ...(parsed.collectorLastRun || {})

      }

    }

  } catch {

    return defaultCollectorState()

  }

}



export async function writeCollectorStateAtomic(state: CollectorState): Promise<void> {

  await ensureCacheDir()

  const path = collectorStateFilePath()

  const tmp = `${path}.${process.pid}.${Date.now()}.tmp`

  await writeFile(tmp, `${JSON.stringify(state, null, 2)}\n`, 'utf8')

  await rename(tmp, path)

}



/** Move legacy collectorLastRun from meta.json into collector-state.json (one-time). */

export async function migrateCollectorStateFromMeta(

  legacyRuns: Partial<Record<string, string>> | undefined

): Promise<void> {

  if (!legacyRuns || !Object.keys(legacyRuns).length) return

  const state = await readCollectorState()

  const merged = { ...state.collectorLastRun, ...legacyRuns }

  if (JSON.stringify(merged) === JSON.stringify(state.collectorLastRun)) return

  state.collectorLastRun = merged

  await writeCollectorStateAtomic(state)

}



export async function readCacheMeta(): Promise<CacheMeta> {

  try {

    const raw = await readFile(metaFilePath(), 'utf8')

    const parsed = JSON.parse(raw) as Record<string, unknown>

    const legacyRuns = parsed.collectorLastRun as Partial<Record<string, string>> | undefined

    if (legacyRuns && Object.keys(legacyRuns).length) {

      await migrateCollectorStateFromMeta(legacyRuns)

      const migrated = parsePanelMeta(parsed)

      await writeCacheMetaAtomic(migrated)

      if (migrated.opRunning && !migrated.opRunningSince) {

        migrated.opRunningSince = new Date().toISOString()

      }

      return migrated

    }

    const meta = parsePanelMeta(parsed)

    if (meta.opRunning && !meta.opRunningSince) {

      meta.opRunningSince = new Date().toISOString()

    }

    return meta

  } catch {

    return defaultCacheMeta()

  }

}



export async function writeCacheMetaAtomic(meta: CacheMeta): Promise<void> {

  await ensureCacheDir()

  const path = metaFilePath()

  const tmp = `${path}.${process.pid}.${Date.now()}.tmp`

  const body: CacheMeta = {

    sections: meta.sections,

    opRunning: meta.opRunning,

    opRunningSince: meta.opRunningSince,

    pausedUntil: meta.pausedUntil,

    pendingForce: meta.pendingForce,

    ...(meta.diskTestActive ? { diskTestActive: true } : {})

  }

  await writeFile(tmp, `${JSON.stringify(body, null, 2)}\n`, 'utf8')

  await rename(tmp, path)

}



export async function mergePresenceSections(

  incoming: CacheSectionKey[],

  domain?: string

): Promise<CacheMeta> {

  const meta = await reconcileOpRunning()

  const now = new Date().toISOString()

  for (const key of incoming) {

    const prev = meta.sections[key] || { lastSeenAt: now }

    meta.sections[key] = {

      ...prev,

      lastSeenAt: now,

      ...(key === 'websites' && domain ? { domain } : {})

    }

  }

  await writeCacheMetaAtomic(meta)

  return meta

}



export async function setCacheOpRunning(running: boolean): Promise<void> {

  const meta = await readCacheMeta()

  meta.opRunning = running

  meta.opRunningSince = running ? new Date().toISOString() : null

  if (!running) {

    meta.pausedUntil = null

  }

  await writeCacheMetaAtomic(meta)

}



export async function setCachePausedUntil(until: Date | null): Promise<void> {

  const meta = await readCacheMeta()

  meta.pausedUntil = until ? until.toISOString() : null

  await writeCacheMetaAtomic(meta)

}



export async function requestForceRefresh(jobName: string): Promise<void> {

  const meta = await readCacheMeta()

  if (!meta.pendingForce.includes(jobName)) {

    meta.pendingForce.push(jobName)

  }

  await writeCacheMetaAtomic(meta)

}



export async function setDiskTestActive(active: boolean): Promise<void> {

  const meta = await readCacheMeta()

  if (active) {

    meta.diskTestActive = true

  } else {

    delete meta.diskTestActive

  }

  await writeCacheMetaAtomic(meta)

}



export function isSectionActive(
  meta: CacheMeta,
  section: CacheSectionKey,
  ttlMs = Number(process.env.DPANEL_PRESENCE_TTL_MS || 45_000)
): boolean {
  const state = meta.sections[section]
  if (!state?.lastSeenAt) return false
  const t = Date.parse(state.lastSeenAt)
  if (Number.isNaN(t)) return false
  return Date.now() - t < ttlMs
}

export function isAnySectionActive(
  meta: CacheMeta,
  sections: CacheSectionKey[],
  ttlMs = Number(process.env.DPANEL_PRESENCE_TTL_MS || 45_000)
): boolean {
  return sections.some((section) => isSectionActive(meta, section, ttlMs))
}



export function isCollectorPaused(meta: CacheMeta): boolean {

  if (meta.opRunning) return true

  if (meta.diskTestActive) return true

  if (meta.pausedUntil) {

    const t = Date.parse(meta.pausedUntil)

    if (!Number.isNaN(t) && Date.now() < t) return true

  }

  return false

}



/** Clear stuck opRunning when no site/system update process is alive (grace + max TTL). */

export async function reconcileOpRunning(): Promise<CacheMeta> {

  const meta = await readCacheMeta()

  if (!meta.opRunning) return meta



  const sinceMs = meta.opRunningSince ? Date.parse(meta.opRunningSince) : NaN

  const ageMs = Number.isFinite(sinceMs) ? Date.now() - sinceMs : opRunningMaxMs() + 1



  const { isAnySiteOpProcessAlive, isSystemUpdateProcessAlive } = await import('./stack')

  const alive = (await isAnySiteOpProcessAlive()) || (await isSystemUpdateProcessAlive())



  if (alive) return meta



  if (ageMs >= opRunningMaxMs() || ageMs >= OP_RUNNING_GRACE_MS) {

    meta.opRunning = false

    meta.opRunningSince = null

    meta.pausedUntil = null

    await writeCacheMetaAtomic(meta)

  }



  return meta

}


