import { sessionCookieName } from '../../utils/session'

export default defineEventHandler((event) => {
  deleteCookie(event, sessionCookieName(), { path: '/' })
  return { ok: true }
})
