import { getCookie } from 'h3'
import { verifySessionToken, sessionCookieName } from './session'

export function requireAuth(event: Parameters<typeof getCookie>[0]) {
  const config = useRuntimeConfig()
  const token = getCookie(event, sessionCookieName())
  const email = verifySessionToken(token, config.sessionSecret)
  if (!email) {
    throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
  }
  return email
}
