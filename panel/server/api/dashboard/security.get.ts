import { requireAuth } from '../../utils/auth-guard'
import {
  attachCacheMeta,
  dashboardCacheReadEnabled,
  readCachePayloadWithFallback
} from '../../utils/cache-read'
import type { HostSecurityStatus } from '../../utils/host-security'
import { fetchHostSecurityStatus } from '../../utils/host-security'
import { queryFail2ban, type Fail2banQueryResult } from '../../utils/fail2ban-host'

type SecurityCachePayload = {
  status?: HostSecurityStatus
  fail2banSummary?: Fail2banQueryResult
}

const EMPTY_STATUS = {
  ok: false,
  fail2ban: { installed: false, active: false, jails: [], bannedIps: [] },
  clamav: {
    installed: false,
    daemonActive: false,
    freshclamActive: false,
    signatureDate: null
  }
}

function mapStatus(status: HostSecurityStatus) {
  return {
    ok: status.ok !== false,
    fail2ban: status.fail2ban ?? EMPTY_STATUS.fail2ban,
    clamav: status.clamav ?? EMPTY_STATUS.clamav,
    ...(status.error ? { error: status.error } : {})
  }
}

function mapFail2ban(summary: Fail2banQueryResult) {
  return {
    ok: summary.ok !== false,
    jails: summary.jails ?? [],
    bannedIps: summary.bannedIps ?? [],
    ...(summary.error ? { error: summary.error } : {})
  }
}

async function fetchLiveSecurity(): Promise<SecurityCachePayload> {
  const [status, fail2banSummary] = await Promise.all([
    fetchHostSecurityStatus(),
    queryFail2ban('summary')
  ])
  return { status, fail2banSummary }
}

/** Cached security snapshot for dashboard Security panel only. */
export default defineEventHandler(async (event) => {
  requireAuth(event)

  if (!dashboardCacheReadEnabled()) {
    try {
      const live = await fetchLiveSecurity()
      return {
        status: mapStatus(live.status ?? EMPTY_STATUS),
        fail2ban: mapFail2ban(live.fail2banSummary ?? { ok: false, installed: false, active: false, version: null, jails: [], bannedIps: [] })
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Could not read host security status'
      return {
        status: { ...EMPTY_STATUS, error: msg },
        fail2ban: { ok: false, jails: [], bannedIps: [], error: msg }
      }
    }
  }

  const { payload, result } = await readCachePayloadWithFallback<SecurityCachePayload>(
    'security.json',
    event,
    fetchLiveSecurity,
    {
      sections: ['dashboard'],
      isPayloadUsable: (p) => !!(p?.status && p?.fail2banSummary)
    }
  )

  const status = payload?.status
  const summary = payload?.fail2banSummary

  if (status && summary) {
    return attachCacheMeta(
      {
        status: mapStatus(status),
        fail2ban: mapFail2ban(summary)
      },
      result
    )
  }

  const error = result.warming ? 'Warming security cache…' : 'Security cache unavailable'
  return attachCacheMeta(
    {
      status: { ...EMPTY_STATUS, error },
      fail2ban: { ok: false, jails: [], bannedIps: [], error }
    },
    result
  )
})
