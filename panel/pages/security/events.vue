<template>
  <div>
    <h1>Security events</h1>
    <p class="page-desc">
      Fail2ban bans, failed logins, and ClamAV detections. Source indicates whether the event came from
      the panel, Fail2ban, or a website path.
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <PageLoader v-if="pending" label="Loading events…" />

    <div v-else-if="!events.length" class="card muted">No security events recorded yet.</div>

    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Time</th>
            <th>Kind</th>
            <th>Source</th>
            <th>IP</th>
            <th>Website</th>
            <th>Path / detail</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="ev in events" :key="ev.id">
            <td class="mono-sm">{{ formatTime(ev.at) }}</td>
            <td>{{ kindLabel(ev.kind) }}</td>
            <td>{{ ev.source }}</td>
            <td>{{ ev.ip || '—' }}</td>
            <td>{{ ev.domain || '—' }}</td>
            <td class="detail-cell">
              <span v-if="ev.path">{{ ev.path }}</span>
              <span v-else-if="ev.detail" class="muted">{{ ev.detail }}</span>
              <span v-else>—</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <footer class="footer-actions">
      <button type="button" class="btn btn-ghost btn-sm" :disabled="pending" @click="refresh">
        <AppIcon name="refresh" :size="14" />
        Refresh
      </button>
    </footer>
  </div>
</template>

<script setup lang="ts">
type SecurityEvent = {
  id: string
  at: string
  kind: string
  source: string
  ip?: string | null
  domain?: string | null
  path?: string | null
  detail?: string | null
}

const { msg, ok, alertKey, clearAlert } = usePageAlert()

const { data, pending, refresh } = useFetch<{ events?: SecurityEvent[] }>('/api/security/events?limit=100', {
  key: 'security-events-page'
})

const events = computed(() => data.value?.events ?? [])

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
      return 'Malware found'
    case 'security_install':
      return 'Packages installed'
    default:
      return kind
  }
}
</script>

<style scoped>
.detail-cell {
  max-width: 280px;
  word-break: break-word;
}

.mono-sm {
  font-size: 0.8125rem;
  white-space: nowrap;
}

.footer-actions {
  margin-top: 1rem;
}
</style>
