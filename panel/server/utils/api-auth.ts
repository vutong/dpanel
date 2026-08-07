import type { H3Event } from 'h3'
import { getHeader, getRequestIP, setHeader } from 'h3'
import {
  permissionSatisfies,
  verifyApiCredentials,
  type ApiKeyPermission,
  type ApiKeyRecord,
} from './api-keys'

/** In-memory: last failed auth attempt per IP (ms). Restart clears. */
const failedAuthByIp = new Map<string, number>()
const FAIL_WINDOW_MS = 1000

function clientIp(event: H3Event): string {
  return (
    getRequestIP(event, { xForwardedFor: true }) ||
    getHeader(event, 'x-real-ip') ||
    'unknown'
  )
}

function recordFailedAuth(event: H3Event): void {
  failedAuthByIp.set(clientIp(event), Date.now())
}

/** Only throttle repeated failures — never block a request before verifying credentials. */
function throwUnauthorized(event: H3Event): never {
  const ip = clientIp(event)
  const last = failedAuthByIp.get(ip)
  const now = Date.now()
  if (last != null && now - last < FAIL_WINDOW_MS) {
    setHeader(event, 'Retry-After', '1')
    throw createError({
      statusCode: 429,
      statusMessage: 'Too many failed authentication attempts',
    })
  }
  recordFailedAuth(event)
  throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
}

/**
 * Validate x-dpanel-api-key + x-dpanel-api-secret against panel api-keys.json.
 * Failed auth (wrong key/secret) is rate-limited to ~1 request/second per IP.
 * Valid credentials are never rate-limited (including right after a prior failure).
 * Valid credentials with insufficient permission → 403 (not rate-limited).
 */
export async function requireApiCredentials(
  event: H3Event,
  minPermission: ApiKeyPermission = 'read',
): Promise<ApiKeyRecord> {
  const apiKey = String(getHeader(event, 'x-dpanel-api-key') || '').trim()
  const apiSecret = String(getHeader(event, 'x-dpanel-api-secret') || '').trim()

  if (!apiKey || !apiSecret) {
    throwUnauthorized(event)
  }

  const record = await verifyApiCredentials(apiKey, apiSecret)
  if (!record) {
    throwUnauthorized(event)
  }

  if (!permissionSatisfies(record.permission, minPermission)) {
    throw createError({
      statusCode: 403,
      statusMessage: 'API key does not have permission for this action',
    })
  }

  return record
}
