import { requireAuth } from '../../../utils/auth-guard'
import { systemUpdateLogPath } from '../../../utils/stack'
import { readFile, stat } from 'node:fs/promises'

const MAX_CHUNK = 96 * 1024

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const offset = Math.max(0, Number(getQuery(event).offset ?? 0) || 0)
  const path = systemUpdateLogPath()

  try {
    const st = await stat(path)
    const size = st.size
    if (offset >= size) {
      return { op: 'update', offset: size, chunk: '', size, full: false }
    }
    const buf = await readFile(path)
    const text = buf.toString('utf8')
    let chunk = text.slice(offset)
    let nextOffset = text.length
    if (chunk.length > MAX_CHUNK) {
      chunk = chunk.slice(0, MAX_CHUNK)
      nextOffset = offset + MAX_CHUNK
    }
    return { op: 'update', offset: nextOffset, chunk, size, full: false }
  } catch {
    return { op: 'update', offset: 0, chunk: '', size: 0, full: false }
  }
})
