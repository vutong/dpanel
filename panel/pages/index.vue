<template>
  <div class="overview">
    <h1>Overview</h1>
    <p class="page-desc">Manage websites and MariaDB on this VPS.</p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <PageLoader v-if="loading" label="Loading overview…" />
    <div v-else class="grid stat-grid">
      <NuxtLink to="/websites" class="card stat-card">
        <div class="stat-icon">
          <AppIcon name="globe" :size="22" />
        </div>
        <div>
          <h2>Websites</h2>
          <p class="stat-value">{{ siteCount }} <span class="stat-unit">site(s)</span></p>
        </div>
      </NuxtLink>
      <NuxtLink to="/databases" class="card stat-card">
        <div class="stat-icon stat-icon-db">
          <AppIcon name="database" :size="22" />
        </div>
        <div>
          <h2>MariaDB</h2>
          <p class="stat-value">{{ dbCount }} <span class="stat-unit">database(s)</span></p>
        </div>
      </NuxtLink>
    </div>

    <DockerStatsPanel />

    <footer class="overview-footer">
      <button
        type="button"
        class="btn btn-sm update-btn"
        :disabled="updateBusy"
        @click="onUpdateClick"
      >
        <AppIcon name="git-pull" :size="14" />
        {{ updateBusy ? 'Updating…' : 'Update Dpanel' }}
      </button>
      <button
        type="button"
        class="btn btn-sm reboot-btn"
        :disabled="rebooting"
        @click="onRebootClick"
      >
        <AppIcon name="power" :size="14" />
        {{ rebooting ? 'Rebooting…' : 'Reboot VPS' }}
      </button>
    </footer>

    <DpanelUpdateStreamModal
      :open="updateOpen"
      @close="onUpdateStreamClose"
      @done="onUpdateDone"
    />
  </div>
</template>

<script setup lang="ts">
const { data: sites, pending: sitesPending } = useFetch('/api/websites')
const { data: dbs, pending: dbsPending } = useFetch('/api/databases')
const loading = computed(() => sitesPending.value || dbsPending.value)
const siteCount = computed(() => sites.value?.sites?.length ?? 0)
const dbCount = computed(() => dbs.value?.databases?.length ?? 0)

const REBOOT_WAIT_KEY = 'dpanel-reboot-waiting'

const rebooting = ref(false)
const updateOpen = ref(false)
const updateBusy = ref(false)
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

let rebootPollTimer: ReturnType<typeof setTimeout> | null = null

function clearRebootPoll() {
  if (rebootPollTimer) {
    clearTimeout(rebootPollTimer)
    rebootPollTimer = null
  }
}

async function pollUntilOnline(attempt = 0) {
  const maxAttempts = 90
  try {
    await $fetch('/api/ping', { timeout: 4000 })
    rebooting.value = false
    sessionStorage.removeItem(REBOOT_WAIT_KEY)
    showAlert('Server is back online.', true)
    return
  } catch {
    if (attempt >= maxAttempts) {
      rebooting.value = false
      sessionStorage.removeItem(REBOOT_WAIT_KEY)
      showAlert('Reboot is taking longer than expected — refresh the page when the panel loads.', false)
      return
    }
    rebootPollTimer = setTimeout(() => void pollUntilOnline(attempt + 1), 4000)
  }
}

function startRebootWatch() {
  sessionStorage.setItem(REBOOT_WAIT_KEY, '1')
  clearRebootPoll()
  rebootPollTimer = setTimeout(() => void pollUntilOnline(0), 8000)
}

async function onUpdateClick() {
  if (
    updateBusy.value ||
    !import.meta.client ||
    !confirm(
      'Update dpanel from GitHub now? This runs sudo dpanel update — the panel may restart and take several minutes.'
    )
  ) {
    return
  }

  updateBusy.value = true
  clearAlert()
  try {
    await $fetch('/api/system/update', { method: 'POST' })
    updateOpen.value = true
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not start update', false)
  } finally {
    updateBusy.value = false
  }
}

function onUpdateStreamClose() {
  updateOpen.value = false
}

function onUpdateDone(payload: { ok: boolean; message: string }) {
  updateBusy.value = false
  if (payload.ok) updateOpen.value = false
  showAlert(payload.message, payload.ok)
}

function onRebootClick() {
  if (
    rebooting.value ||
    !import.meta.client ||
    !confirm('Reboot this VPS now? All websites and the panel will be offline for a minute.')
  ) {
    return
  }
  rebooting.value = true
  void $fetch('/api/system/reboot', { method: 'POST' })
  startRebootWatch()
}

onMounted(() => {
  if (!import.meta.client) return
  if (sessionStorage.getItem(REBOOT_WAIT_KEY) === '1') {
    rebooting.value = true
    startRebootWatch()
  }
  void $fetch<{ status?: string }>('/api/system/update/operation')
    .then((s) => {
      if (s.status === 'running') {
        updateBusy.value = true
        updateOpen.value = true
      }
    })
    .catch(() => {})
})

onUnmounted(() => {
  clearRebootPoll()
})
</script>

<style scoped>
.page-desc {
  color: var(--muted);
  margin: 0.35rem 0 1.25rem;
  font-size: 0.95rem;
}

.stat-grid {
  margin-bottom: 2rem;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 1rem;
}

.stat-card {
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  text-decoration: none;
  color: inherit;
  transition:
    border-color 0.15s,
    box-shadow 0.15s,
    transform 0.15s;
}

.stat-card:hover {
  border-color: var(--accent);
  box-shadow: var(--shadow-md);
  transform: translateY(-2px);
  text-decoration: none;
}

.stat-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  border-radius: 10px;
  background: var(--accent-muted);
  color: var(--accent);
  flex-shrink: 0;
}

.stat-icon-db {
  background: var(--success-muted);
  color: var(--success);
}

.stat-card h2 {
  font-size: 1rem;
  margin-bottom: 0.35rem;
  color: var(--text);
}

.stat-value {
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--text);
}

.stat-unit {
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--muted);
}

.overview-footer {
  margin-top: 2rem;
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
}

.update-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  border: 1px solid var(--accent);
  background: transparent;
  color: var(--accent);
}

.update-btn:hover:not(:disabled) {
  background: var(--accent-muted);
  border-color: var(--accent);
  color: var(--accent);
}

.reboot-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  border: 1px solid var(--danger);
  background: transparent;
  color: var(--danger);
}

.reboot-btn:hover:not(:disabled) {
  background: var(--danger-muted);
  border-color: var(--danger);
  color: var(--danger);
}
</style>
