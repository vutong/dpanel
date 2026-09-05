import { requireAuth } from '../../utils/auth-guard'
import { attachCacheMeta, cacheReadEnabled } from '../../utils/cache-read'
import {
  mergeDatabasesList,
  readCache,
  readDatabasesJson,
  setCacheResponseHeaders
} from '../../utils/cache-store'
import { runScript, scriptErrorMessage } from '../../utils/stack'

export type DatabaseEntry = {
  name: string
  user: string
  siteDomain?: string | null
  createdAt?: string | null
}

export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (!cacheReadEnabled()) {
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
  }

  const [cacheResult, registryRows] = await Promise.all([
    readCache<DatabaseEntry[]>('databases-list.json'),
    readDatabasesJson()
  ])
  setCacheResponseHeaders(event, cacheResult)

  const cacheRows = Array.isArray(cacheResult.envelope?.data)
    ? (cacheResult.envelope.data as DatabaseEntry[])
    : undefined

  if (
    (!cacheRows || !cacheRows.length) &&
    (cacheResult.warming || !cacheResult.envelope)
  ) {
    try {
      const out = await runScript('db-list.sh', [], 60_000)
      const shellRows = JSON.parse(out.trim()) as DatabaseEntry[]
      if (Array.isArray(shellRows) && shellRows.length) {
        const databases = mergeDatabasesList(shellRows, registryRows || undefined) as DatabaseEntry[]
        return attachCacheMeta({ databases }, freshResult())
      }
    } catch {
      /* merge registry only below */
    }
  }

  const databases = mergeDatabasesList(cacheRows, registryRows || undefined) as DatabaseEntry[]

  return attachCacheMeta({ databases }, cacheResult)
})

function freshResult(): import('../../utils/cache-store').ReadCacheResult {
  return {
    envelope: null,
    ageSec: 0,
    isStale: false,
    warming: false,
    fromL1: false
  }
}
