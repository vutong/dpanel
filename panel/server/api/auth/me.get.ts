import { getCookie } from 'h3'
import { requireAuth } from '../../utils/auth-guard'
import { sessionCookieName, verifySessionToken } from '../../utils/session'

export default defineEventHandler((event) => {
  try {
    const email = requireAuth(event)
    return { authenticated: true, email }
  } catch {
    const config = useRuntimeConfig()
    const token = getCookie(event, sessionCookieName())
    const email = verifySessionToken(token, config.sessionSecret)
    return { authenticated: !!email, email: email || null }
  }
})
