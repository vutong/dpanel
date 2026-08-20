<template>
  <div class="card security-dashboard">
    <div class="head">
      <h2>
        <AppIcon name="shield" :size="18" />
        Security
      </h2>
      <NuxtLink to="/settings/fail2ban" class="link-sm">Fail2ban</NuxtLink>
    </div>

    <PageLoader v-if="pending" label="Loading security…" />

    <template v-else>
      <div class="status-row">
        <div v-if="fail2banOk" class="status-active">Fail2ban: Active</div>
        <div v-else class="pill pill-warn">
          Fail2ban: {{ fail2banLabel }}
        </div>
        <div v-if="clamOk" class="status-active">ClamAV: Active</div>
        <div v-else class="pill pill-warn">
          ClamAV: {{ clamLabel }}
        </div>
      </div>

      <p v-if="!installedAny" class="muted hint">
        Host security packages not installed.
        <NuxtLink to="/settings/fail2ban">Fail2ban</NuxtLink>
        ·
        <NuxtLink to="/settings/clamav">ClamAV</NuxtLink>
      </p>

      <p v-else class="muted">Use Fail2ban and ClamAV pages to manage host security.</p>
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
  if (!status.value?.fail2ban?.installed) return 'not installed'
  return status.value.fail2ban.active ? 'active' : 'inactive'
})
const clamLabel = computed(() => {
  if (!status.value?.clamav?.installed) return 'not installed'
  return status.value.clamav.daemonActive ? 'active' : 'inactive'
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

.hint {
  font-size: var(--text-sm);
  margin: 0 0 0.75rem;
}

</style>
