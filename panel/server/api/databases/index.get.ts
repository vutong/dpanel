import { requireAuth } from '../../utils/auth-guard'
import { runScript, scriptErrorMessage } from '../../utils/stack'

export type DatabaseEntry = {
  name: string
  user: string
  createdAt?: string | null
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  try {
    const out = await runScript('db-list.sh', [], 60_000)
    const databases = JSON.parse(out.trim()) as DatabaseEntry[]
    return { databases: Array.isArray(databases) ? databases : [] }
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
