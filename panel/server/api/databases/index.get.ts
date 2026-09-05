import { requireAuth } from '../../utils/auth-guard'
import { mergeDatabasesList, readDatabasesJson } from '../../utils/cache-store'
import { runScript, scriptErrorMessage } from '../../utils/stack'

export type DatabaseEntry = {
  name: string
  user: string
  siteDomain?: string | null
  createdAt?: string | null
}

async function fetchDatabasesFromShell(): Promise<DatabaseEntry[]> {
  const out = await runScript('db-list.sh', [], 60_000)
  const rows = JSON.parse(out.trim()) as DatabaseEntry[]
  return Array.isArray(rows) ? rows : []
}

/** Live MariaDB list — no cache (business page). */
export default defineEventHandler(async (event) => {
  requireAuth(event)

  try {
    const [shellRows, registryRows] = await Promise.all([
      fetchDatabasesFromShell(),
      readDatabasesJson()
    ])
    const databases = mergeDatabasesList(shellRows, registryRows || undefined) as DatabaseEntry[]
    return { databases }
  } catch (e: unknown) {
    throw createError({
      statusCode: 500,
      statusMessage: scriptErrorMessage(e)
    })
  }
})
