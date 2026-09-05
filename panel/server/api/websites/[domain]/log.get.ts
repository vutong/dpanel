import { requireAuth } from '../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../utils/sites'
import { domainSlug, runScript, siteOpLogPath, type SiteLogKind } from '../../../utils/stack'
import { readMicroCache, writeMicroCache } from '../../../utils/cache-store'
import { readFile, stat } from 'node:fs/promises'

const MAX_CHUNK = 96 * 1024
const FILE_OPS = new Set<SiteLogKind>(['update', 'rebuild', 'create', 'fix-permissions'])
const MICRO_CACHE_MS = 2000

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))

  const op = String(getQuery(event).op || 'rebuild').trim() as SiteLogKind
  if (!FILE_OPS.has(op) && op !== 'container') {
    throw createError({
      statusCode: 400,
      statusMessage: 'Query op must be rebuild, update, create, fix-permissions, or container'
    })
  }

  if (op === 'container') {
    let chunk = ''
    try {
      chunk = await runScript('site-app-logs.sh', [domain, '400'], 60_000)
    } catch (e: unknown) {
      chunk = e instanceof Error ? e.message : 'Could not read container logs'
    }
    return {
      domain,
      op,
      offset: chunk.length,
      chunk,
      size: chunk.length,
      slug: domainSlug(domain),
      full: true
    }
  }

  const offset = Math.max(0, Number(getQuery(event).offset ?? 0) || 0)
  const cacheKey = `site-log:${domain}:${op}:${offset}`
  const cached = readMicroCache<Record<string, unknown>>(cacheKey, MICRO_CACHE_MS)
  if (cached) {
    return cached
  }

  const path = siteOpLogPath(domain, op)

  try {
    const st = await stat(path)
    const size = st.size
    if (offset >= size) {
      const empty = { domain, op, offset: size, chunk: '', size, slug: domainSlug(domain), full: false }
      writeMicroCache(cacheKey, empty)
      return empty
    }
    const buf = await readFile(path)
    const text = buf.toString('utf8')
    let chunk = text.slice(offset)
    let nextOffset = text.length
    if (chunk.length > MAX_CHUNK) {
      chunk = chunk.slice(0, MAX_CHUNK)
      nextOffset = offset + MAX_CHUNK
    }
    const result = { domain, op, offset: nextOffset, chunk, size, slug: domainSlug(domain), full: false }
    writeMicroCache(cacheKey, result)
    return result
  } catch {
    const empty = { domain, op, offset: 0, chunk: '', size: 0, slug: domainSlug(domain), full: false }
    writeMicroCache(cacheKey, empty)
    return empty
  }
})
