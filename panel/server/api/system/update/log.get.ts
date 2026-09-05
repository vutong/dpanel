import { requireAuth } from '../../../utils/auth-guard'
import { systemUpdateLogPath } from '../../../utils/stack'
import { readMicroCache, writeMicroCache } from '../../../utils/cache-store'
import { readFile, stat } from 'node:fs/promises'

const MAX_CHUNK = 96 * 1024
const MICRO_CACHE_MS = 2000

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const offset = Math.max(0, Number(getQuery(event).offset ?? 0) || 0)
  const cacheKey = `system-update-log:${offset}`
  const cached = readMicroCache<Record<string, unknown>>(cacheKey, MICRO_CACHE_MS)
  if (cached) {
    return cached
  }

  const path = systemUpdateLogPath()

  try {
    const st = await stat(path)
    const size = st.size
    if (offset >= size) {
      const empty = { op: 'update', offset: size, chunk: '', size, full: false }
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
    const result = { op: 'update', offset: nextOffset, chunk, size, full: false }
    writeMicroCache(cacheKey, result)
    return result
  } catch {
    const empty = { op: 'update', offset: 0, chunk: '', size: 0, full: false }
    writeMicroCache(cacheKey, empty)
    return empty
  }
})
