<template>
  <div class="card security-overview">
    <div class="head">
      <h2>
        <AppIcon name="shield" :size="18" />
        Security
      </h2>
      <NuxtLink to="/security/events" class="link-sm">All events</NuxtLink>
    </div>

    <PageLoader v-if="pending" label="Loading security…" />

    <template v-else>
      <div class="status-row">
        <div class="pill" :class="fail2banOk ? 'pill-ok' : 'pill-warn'">
          Fail2ban: {{ fail2banLabel }}
        </div>
        <div class="pill" :class="clamOk ? 'pill-ok' : 'pill-warn'">
          ClamAV: {{ clamLabel }}
        </div>
      </div>

      <p v-if="!installedAny" class="muted hint">
        Host security packages not installed.
        <NuxtLink to="/settings/fail2ban">Fail2ban</NuxtLink>
        ·
        <NuxtLink to="/settings/clamav">ClamAV</NuxtLink>
      </p>

      <div v-if="events.length" class="events-mini">
        <p class="sub">Recent events</p>
        <ul>
          <li v-for="ev in events" :key="ev.id">
            <span class="ev-time">{{ formatTime(ev.at) }}</span>
            <span class="ev-kind">{{ kindLabel(ev.kind) }}</span>
            <span v-if="ev.ip" class="ev-meta">{{ ev.ip }}</span>
            <span v-if="ev.domain" class="ev-meta">{{ ev.domain }}</span>
          </li>
        </ul>
      </div>
      <p v-else class="muted">No security events yet.</p>
    </template>
  </div>
</template>

<script setup lang="ts">
type SecurityEvent = {
  id: string
  at: string
  kind: string
  ip?: string | null
  domain?: string | null
}

type Status = {
  fail2ban?: { installed?: boolean; active?: boolean }
  clamav?: { installed?: boolean; daemonActive?: boolean }
}

const { data: status, pending: statusPending } = useFetch<Status>('/api/security/status', {
  key: 'security-status-overview'
})
const { data: evData, pending: evPending } = useFetch<{ events?: SecurityEvent[] }>(
  '/api/security/events?limit=5',
  { key: 'security-events-overview' }
)

const pending = computed(() => statusPending.value || evPending.value)
const events = computed(() => evData.value?.events ?? [])

const fail2banOk = computed(
  () => status.value?.fail2ban?.installed && status.value?.fail2ban?.active
)
const clamOk = computed(
  () => status.value?.clamav?.installed && status.value?.clamav?.daemonActive
)
const installedAny = computed(
  () => status.value?.fail2ban?.installed || status.value?.clamav?.installed
)

const fail2banLabel = computed(() => {
  if (!status.value?.fail2ban?.installed) return 'not installed'
  return status.value.fail2ban.active ? 'active' : 'inactive'
})
const clamLabel = computed(() => {
  if (!status.value?.clamav?.installed) return 'not installed'
  return status.value.clamav.daemonActive ? 'active' : 'inactive'
})

function formatTime(iso: string) {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

function kindLabel(kind: string) {
  switch (kind) {
    case 'fail2ban_ban':
      return 'IP banned'
    case 'login_brute':
      return 'Login failed'
    case 'malware_found':
      return 'Malware'
    case 'security_install':
      return 'Installed'
    default:
      return kind
  }
}
</script>

<style scoped>
.security-overview {
  margin-top: 1.25rem;
}

.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}

.head h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  font-size: 1rem;
}

.link-sm {
  font-size: 0.8125rem;
  color: var(--accent);
}

.status-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
}

.pill {
  font-size: 0.8125rem;
  padding: 0.25rem 0.625rem;
  border-radius: 999px;
  background: var(--surface-2);
}

.pill-ok {
  color: var(--success, #16a34a);
}

.pill-warn {
  color: var(--warning, #ca8a04);
}

.hint {
  font-size: 0.875rem;
  margin: 0 0 0.75rem;
}

.sub {
  font-size: 0.8125rem;
  color: var(--muted);
  margin: 0 0 0.375rem;
}

.events-mini ul {
  list-style: none;
  margin: 0;
  padding: 0;
}

.events-mini li {
  font-size: 0.8125rem;
  padding: 0.25rem 0;
  border-bottom: 1px solid var(--border);
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.ev-time {
  color: var(--muted);
  min-width: 8rem;
}

.ev-kind {
  font-weight: 500;
}

.ev-meta {
  color: var(--muted);
}

.muted {
  color: var(--muted);
  font-size: 0.875rem;
}
</style>
