import { requireAuth } from '../../../utils/auth-guard'
import { systemUpdateStatusPath, type SystemUpdateStatus } from '../../../utils/stack'
import { readFile } from 'node:fs/promises'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  try {
    const raw = await readFile(systemUpdateStatusPath(), 'utf8')
    return JSON.parse(raw) as SystemUpdateStatus
  } catch {
    return { op: 'update', status: 'none' as const } satisfies SystemUpdateStatus
  }
})
