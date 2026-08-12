import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import {
  fileReadStream,
  imageContentType,
  isImageName,
  MAX_PREVIEW_IMAGE_BYTES,
  openFileForRead,
  previewText
} from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const path = String(getQuery(event).path || '')
  const { target, size } = await openFileForRead(domain, path)
  const name = target.rel.split('/').pop() || target.rel

  if (isImageName(name)) {
    if (size > MAX_PREVIEW_IMAGE_BYTES) {
      throw createError({
        statusCode: 413,
        statusMessage: `Image too large to preview (max ${MAX_PREVIEW_IMAGE_BYTES / 1024 / 1024} MB)`
      })
    }
    setHeader(event, 'Content-Type', imageContentType(name))
    setHeader(event, 'Content-Length', String(size))
    setHeader(event, 'Cache-Control', 'private, no-store')
    return sendStream(event, fileReadStream(target.abs))
  }

  return previewText(domain, path)
})
