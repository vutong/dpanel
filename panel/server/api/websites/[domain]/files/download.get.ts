import { basename } from 'node:path'
import { requireAuth } from '../../../../utils/auth-guard'
import { normalizeSiteDomain } from '../../../../utils/sites'
import { fileReadStream, openFileForRead } from '../../../../utils/site-files'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = normalizeSiteDomain(decodeURIComponent(getRouterParam(event, 'domain') || ''))
  const path = String(getQuery(event).path || '')
  const { target, size } = await openFileForRead(domain, path)
  const name = basename(target.rel) || 'download'
  setHeader(event, 'Content-Type', 'application/octet-stream')
  setHeader(event, 'Content-Length', String(size))
  setHeader(
    event,
    'Content-Disposition',
    `attachment; filename="${encodeURIComponent(name)}"; filename*=UTF-8''${encodeURIComponent(name)}`
  )
  return sendStream(event, fileReadStream(target.abs))
})
