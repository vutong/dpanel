import { getQuery } from 'h3'
import { requireAuth } from '../../utils/auth-guard'
import { readSecurityEvents, type SecurityEventSource } from '../../utils/security-events'

const MAX_LIMIT = 350
const DEFAULT_LIMIT = 25

export default defineEventHandler(async (event) => {
  requireAuth(event)

  const query = getQuery(event)
  const rawLimit = Number(query.limit ?? DEFAULT_LIMIT)
  const limit = Math.max(
    1,
    Math.min(MAX_LIMIT, Number.isFinite(rawLimit) ? Math.floor(rawLimit) : DEFAULT_LIMIT)
  )
  const source = typeof query.source === 'string' ? query.source : ''
  const sinceRaw = typeof query.since === 'string' ? Date.parse(query.since) : Number.NaN
  const ip = typeof query.ip === 'string' ? query.ip.trim().toLowerCase() : ''
  const domain = typeof query.domain === 'string' ? query.domain.trim().toLowerCase() : ''

  let events = readSecurityEvents()
  if (source) {
    events = events.filter((item) => item.source === (source as SecurityEventSource))
  }
  if (Number.isFinite(sinceRaw)) {
    events = events.filter((item) => {
      const t = Date.parse(item.at)
      return Number.isFinite(t) && t >= sinceRaw
    })
  }
  if (ip) {
    events = events.filter((item) => (item.ip || '').toLowerCase().includes(ip))
  }
  if (domain) {
    events = events.filter((item) => (item.domain || '').toLowerCase() === domain)
  }

  return {
    ok: true,
    limit,
    events: events.slice(0, limit)
  }
})
