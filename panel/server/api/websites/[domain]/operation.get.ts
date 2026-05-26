import { requireAuth } from '../../../utils/auth-guard'
import { stackRoot } from '../../../utils/stack'
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

export type SiteOperationStatus = {
  domain?: string
  op?: string
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
  updatedAt?: string
}

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const domain = decodeURIComponent(getRouterParam(event, 'domain') || '').trim().toLowerCase()
  if (!domain) {
    throw createError({ statusCode: 400, statusMessage: 'Domain is required' })
  }

  const path = join(stackRoot(), 'data', 'panel', 'site-ops', `${domain}.json`)
  try {
    const raw = await readFile(path, 'utf8')
    return JSON.parse(raw) as SiteOperationStatus
  } catch {
    return { domain, status: 'none' as const }
  }
})
