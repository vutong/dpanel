import { requireAuth } from '../../../utils/auth-guard'
import { domainSlug, siteOpLogPath, type SiteOpKind } from '../../../utils/stack'
import { readFile, stat } from 'node:fs/promises'

const MAX_CHUNK = 96 * 1024

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '')
    .trim()
    .toLowerCase()
  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const op = String(getQuery(event).op || '').trim() as SiteOpKind
  if (op !== 'update' && op !== 'rebuild') {
    throw createError({ statusCode: 400, statusMessage: 'Query op must be update or rebuild' })
  }

  const offset = Math.max(0, Number(getQuery(event).offset ?? 0) || 0)
  const path = siteOpLogPath(domain, op)

  try {
    const st = await stat(path)
    const size = st.size
    if (offset >= size) {
      return { domain, op, offset: size, chunk: '', size, slug: domainSlug(domain) }
    }
    const buf = await readFile(path)
    const text = buf.toString('utf8')
    let chunk = text.slice(offset)
    let nextOffset = text.length
    if (chunk.length > MAX_CHUNK) {
      chunk = chunk.slice(0, MAX_CHUNK)
      nextOffset = offset + MAX_CHUNK
    }
    return { domain, op, offset: nextOffset, chunk, size, slug: domainSlug(domain) }
  } catch {
    return { domain, op, offset: 0, chunk: '', size: 0, slug: domainSlug(domain) }
  }
})
