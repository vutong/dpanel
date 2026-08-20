import { getQuery } from 'h3'
import { requireAuth } from '../../utils/auth-guard'
import { readSecurityEvents, type SecurityEventSource } from '../../utils/security-events'

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const query = getQuery(event)
  const limit = Math.max(1, Math.min(100, Number(query.limit || 100) || 100))
  const source = typeof query.source === 'string' ? query.source : ''

  let events = readSecurityEvents()
  if (source) {
    events = events.filter((item) => item.source === (source as SecurityEventSource))
  }

  return {
    ok: true,
    events: events.slice(0, limit)
  }
})
