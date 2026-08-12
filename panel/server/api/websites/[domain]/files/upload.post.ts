import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import { MAX_UPLOAD_BYTES, uploadToDir } from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))

  const len = Number(getHeader(event, 'content-length') || 0)
  if (Number.isFinite(len) && len > MAX_UPLOAD_BYTES + 1024 * 1024) {
    throw createError({ statusCode: 413, statusMessage: 'File too large (max 64 MB)' })
  }

  const parts = await readMultipartFormData(event)
  if (!parts?.length) {
    throw createError({ statusCode: 400, statusMessage: 'multipart body required' })
  }

  const dirPart = parts.find((p) => p.name === 'path' && !p.filename)
  const destDir = dirPart?.data ? dirPart.data.toString('utf8') : ''

  const files = parts.filter((p) => p.filename && p.data)
  if (!files.length) {
    throw createError({ statusCode: 400, statusMessage: 'No file uploaded' })
  }

  const uploaded: { path: string; name: string; bytes: number }[] = []
  for (const file of files) {
    const raw = file.data
    if (!raw) {
      throw createError({ statusCode: 400, statusMessage: 'Invalid file data' })
    }
    const data = Buffer.isBuffer(raw) ? raw : Buffer.from(raw)
    if (data.byteLength > MAX_UPLOAD_BYTES) {
      throw createError({ statusCode: 413, statusMessage: 'File too large (max 64 MB)' })
    }
    const result = await uploadToDir(domain, destDir, file.filename || 'upload', data)
    uploaded.push(result)
  }

  return { ok: true as const, uploaded }
})
