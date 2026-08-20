<template>
  <aside class="host-metrics security-metrics" aria-label="Security">
    <h3 class="metrics-title">Security</h3>

    <PageLoader v-if="pending" label="Loading…" />

    <template v-else>
      <div class="svc-list">
        <div class="svc-row">
          <NuxtLink to="/settings/fail2ban" class="svc-name">Fail2ban</NuxtLink>
          <span v-if="fail2banOk" class="status-active">Active</span>
          <span v-else class="status-inactive">{{ fail2banLabel }}</span>
        </div>
        <div class="svc-row">
          <NuxtLink to="/settings/clamav" class="svc-name">ClamAV</NuxtLink>
          <span v-if="clamOk" class="status-active">Active</span>
          <span v-else class="status-inactive">{{ clamLabel }}</span>
        </div>
      </div>

      <p v-if="!installedAny" class="hint muted">
        Not installed yet — open Fail2ban or ClamAV to set up.
      </p>
    </template>
  </aside>
</template>

<script setup lang="ts">
type Status = {
  fail2ban?: { installed?: boolean; active?: boolean }
  clamav?: { installed?: boolean; daemonActive?: boolean }
}

const { data: status, pending: statusPending } = useFetch<Status>('/api/security/status', {
  key: 'security-status-dashboard'
})

const pending = computed(() => statusPending.value)

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
  if (!status.value?.fail2ban?.installed) return 'Not installed'
  return status.value.fail2ban.active ? 'Active' : 'Inactive'
})
const clamLabel = computed(() => {
  if (!status.value?.clamav?.installed) return 'Not installed'
  return status.value.clamav.daemonActive ? 'Active' : 'Inactive'
})
</script>

<style scoped>
.host-metrics {
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 1rem 1rem 0.85rem;
}

.metrics-title {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--muted);
  margin: 0 0 0.85rem;
  font-weight: 600;
}

.svc-list {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
}

.svc-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
}

.svc-name {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--text);
  text-decoration: none;
}

.svc-name:hover {
  color: var(--accent);
}

.hint {
  margin: 0.75rem 0 0;
  font-size: 0.75rem;
  line-height: 1.4;
}
</style>
