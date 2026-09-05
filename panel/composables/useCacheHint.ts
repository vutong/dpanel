export type CacheMetaFields = {
  ageSec: number
  stale: boolean
  warming: boolean
}

export function formatCacheHint(
  cache: CacheMetaFields | undefined | null,
  opts?: { warmingLabel?: string; hasData?: boolean }
): string {
  if (!cache) return ''
  const hasData = opts?.hasData !== false
  if (cache.warming && !hasData) {
    return opts?.warmingLabel || 'Warming cache…'
  }
  if (cache.warming || cache.stale) {
    return `Updated ${cache.ageSec}s ago${cache.warming ? ' (warming)' : cache.stale ? ' (stale)' : ''}`
  }
  if (cache.ageSec >= 8) {
    return `Updated ${cache.ageSec}s ago`
  }
  return ''
}

export function pickOldestCache(
  caches: Array<CacheMetaFields | undefined | null>
): CacheMetaFields | null {
  let best: CacheMetaFields | null = null
  for (const c of caches) {
    if (!c) continue
    if (!best || c.ageSec > best.ageSec) best = c
  }
  return best
}
