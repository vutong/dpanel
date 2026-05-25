import { requireAuth } from '../utils/auth-guard'

export default defineEventHandler((event) => {
  requireAuth(event)
  const host = getRequestHeader(event, 'host') || 'localhost'
  const proto = getRequestHeader(event, 'x-forwarded-proto') || 'http'
  const url = `${proto}://${host}/pma/`
  return { url }
})
