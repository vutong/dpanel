import bcrypt from 'bcryptjs'
import { readAuth } from '../../utils/stack'
import { createSessionToken, sessionCookieName } from '../../utils/session'

export default defineEventHandler(async (event) => {
  const body = await readBody<{ email?: string; password?: string }>(event)
  const email = (body.email || '').trim().toLowerCase()
  const password = body.password || ''

  if (!email || !password) {
    throw createError({ statusCode: 400, statusMessage: 'Email and password are required' })
  }

  let auth: { email: string; passwordHash: string }
  try {
    auth = await readAuth()
  } catch {
    throw createError({ statusCode: 500, statusMessage: 'Auth not configured — run install.sh' })
  }

  const authEmail = auth.email.trim().toLowerCase()
  if (email !== authEmail) {
    throw createError({ statusCode: 401, statusMessage: 'Invalid email or password' })
  }

  const hash = auth.passwordHash.startsWith('$2')
    ? auth.passwordHash
    : `$2y${auth.passwordHash.slice(3)}`

  const ok = await bcrypt.compare(password, hash.replace(/^\$2y\$/, '$2a$'))
  if (!ok) {
    throw createError({ statusCode: 401, statusMessage: 'Invalid email or password' })
  }

  const config = useRuntimeConfig()
  const token = createSessionToken(email, config.sessionSecret)

  setCookie(event, sessionCookieName(), token, {
    httpOnly: true,
    sameSite: 'lax',
    path: '/',
    maxAge: 7 * 24 * 60 * 60
  })

  return { ok: true, email }
})
