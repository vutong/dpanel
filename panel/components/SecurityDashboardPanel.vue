<template>
  <div class="card security-dashboard">
    <div class="head">
      <h2>
        <AppIcon name="shield" :size="18" />
        Security
      </h2>
    </div>

    <PageLoader v-if="pending" label="Loading security…" />

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

      <p v-if="!installedAny" class="muted hint">
        Host security packages are not installed yet. Open Fail2ban or ClamAV to install.
      </p>
    </template>
  </div>
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
.security-dashboard {
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

.svc-list {
  display: flex;
  flex-direction: column;
}

.svc-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.65rem 0;
  border-bottom: 1px solid var(--border);
}

.svc-row:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.svc-row:first-child {
  padding-top: 0;
}

.svc-name {
  font-size: var(--text-sm);
  font-weight: 600;
  color: var(--text);
  text-decoration: none;
}

.svc-name:hover {
  color: var(--accent);
}

.hint {
  font-size: var(--text-sm);
  margin: 0.75rem 0 0;
  padding-top: 0.75rem;
  border-top: 1px solid var(--border);
}
</style>
