import { requireAuth } from '../../utils/auth-guard'
import { readSecurityEvents } from '../../utils/security-events'

export default defineEventHandler(async (event) => {
  requireAuth(event)
  const query = getQuery(event)
  const limit = Math.min(Math.max(Number(query.limit) || 50, 1), 200)
  const source = String(query.source || '').trim()
  let events = readSecurityEvents()
  if (source) {
    events = events.filter((ev) => ev.source === source)
  }
  events = events.slice(0, limit)
  return { ok: true, events, total: events.length }
})
