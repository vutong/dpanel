import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto'

const COOKIE = 'dpanel_session'

export function sessionCookieName() {
  return COOKIE
}

function sign(payload: string, secret: string) {
  return createHmac('sha256', secret).update(payload).digest('base64url')
}

export function createSessionToken(email: string, secret: string) {
  const exp = Date.now() + 7 * 24 * 60 * 60 * 1000
  const payload = Buffer.from(JSON.stringify({ email, exp })).toString('base64url')
  const sig = sign(payload, secret)
  return `${payload}.${sig}`
}

export function verifySessionToken(token: string | undefined, secret: string): string | null {
  if (!token) return null
  const [payload, sig] = token.split('.')
  if (!payload || !sig) return null
  const expected = sign(payload, secret)
  try {
    if (!timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null
  } catch {
    return null
  }
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString()) as {
      email: string
      exp: number
    }
    if (data.exp < Date.now()) return null
    return data.email
  } catch {
    return null
  }
}

export function randomToken() {
  return randomBytes(32).toString('hex')
}
