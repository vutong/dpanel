import { requireAuth } from '../../utils/auth-guard'
import { parseScriptJson, runScript } from '../../utils/stack'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const body = await readBody<{ name?: string; user?: string; password?: string }>(event)
  const name = (body.name || '').trim()
  if (!name) {
    throw createError({ statusCode: 400, statusMessage: 'Database name is required' })
  }

  const args = [name]
  if (body.user) args.push(body.user)
  if (body.password) args.push(body.password)

  try {
    const out = await runScript('db-create.sh', args)
    return parseScriptJson(out)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Failed to create database'
    throw createError({ statusCode: 500, statusMessage: msg })
  }
})
