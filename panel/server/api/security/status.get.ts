import { requireAuth } from '../../utils/auth-guard'
import {
  attachCacheMeta,
  cacheReadEnabled,
  readCachePayloadWithFallback
} from '../../utils/cache-read'
import type { HostSecurityStatus } from '../../utils/host-security'
import { fetchHostSecurityStatus } from '../../utils/host-security'

type SecurityCachePayload = {
  status?: HostSecurityStatus
}

const EMPTY: HostSecurityStatus = {
  ok: false,
  fail2ban: { installed: false, active: false, jails: [], bannedIps: [] },
  clamav: {
    installed: false,
    daemonActive: false,
    freshclamActive: false,
    signatureDate: null
  }
}

const ACTIVE_SECTIONS = ['dashboard', 'settings'] as const

export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (!cacheReadEnabled()) {
    try {
      return await fetchHostSecurityStatus()
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Could not read host security status'
      return { ...EMPTY, error: msg }
    }
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityCachePayload>(
    'security.json',
    event,
    async () => {
      const status = await fetchHostSecurityStatus()
      return { status }
    },
    { sections: [...ACTIVE_SECTIONS] }
  )
  const status = payload?.status

  if (status && typeof status === 'object') {
    return attachCacheMeta(
      {
        ok: status.ok !== false,
        fail2ban: status.fail2ban ?? EMPTY.fail2ban,
        clamav: status.clamav ?? EMPTY.clamav,
        ...(status.error ? { error: status.error } : {})
      },
      result
    )
  }

  return attachCacheMeta(
    { ...EMPTY, error: result.warming ? 'Warming security cache…' : 'Security cache unavailable' },
    result
  )
})
