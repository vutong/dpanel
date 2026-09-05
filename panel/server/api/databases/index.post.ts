import { requireAuth } from '../../utils/auth-guard'
import { requestForceRefresh } from '../../utils/cache-meta'
import { parseScriptJson, runScript } from '../../utils/stack'
import { assertSiteActive, getSite, normalizeSiteDomain } from '../../utils/sites'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{
    name?: string
    siteDomain?: string
    user?: string
    password?: string
  }>(event)
  const name = (body.name || '').trim()
  const rawSiteDomain = (body.siteDomain || '').trim()
  if (!name) {
    throw createError({ statusCode: 400, statusMessage: 'Database name is required' })
  }
  if (!rawSiteDomain) {
    throw createError({
      statusCode: 400,
      statusMessage: 'Website is required — every database must belong to a site'
    })
  }
  const siteDomain = normalizeSiteDomain(rawSiteDomain)
  const user = (body.user || '').trim()
  const password = typeof body.password === 'string' ? body.password : ''

  assertSiteActive(await getSite(siteDomain))

  const args = [name, siteDomain]
  if (user) {
    args.push(user)
    if (password) args.push(password)
  } else if (password) {
    args.push('', password)
  }

  try {
    const out = await runScript('db-create.sh', args)
    const result = parseScriptJson(out)
    await requestForceRefresh('databases-list')
    return result
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Failed to create database'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
