<template>
  <div class="dashboard">
    <h1>Dashboard</h1>
    <p class="page-desc">Manage websites and MariaDB on this VPS.</p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <div class="grid stat-grid">
      <NuxtLink to="/websites" class="card stat-card">
        <div class="stat-icon stat-icon-node">
          <AppIcon name="cpu" :size="22" />
        </div>
        <div>
          <h2>NODE</h2>
          <p class="stat-value">
            <span v-if="summaryPending" class="skeleton skeleton-text-lg" aria-hidden="true" />
            <template v-else>
              {{ nodeCount }} <span class="stat-unit">site(s)</span>
            </template>
          </p>
        </div>
      </NuxtLink>
      <NuxtLink to="/websites" class="card stat-card">
        <div class="stat-icon stat-icon-php">
          <AppIcon name="layers" :size="22" />
        </div>
        <div>
          <h2>PHP</h2>
          <p class="stat-value">
            <span v-if="summaryPending" class="skeleton skeleton-text-lg" aria-hidden="true" />
            <template v-else>
              {{ phpCount }} <span class="stat-unit">site(s)</span>
            </template>
          </p>
        </div>
      </NuxtLink>
      <NuxtLink to="/databases" class="card stat-card">
        <div class="stat-icon stat-icon-db">
          <AppIcon name="database" :size="22" />
        </div>
        <div>
          <h2>MariaDB</h2>
          <p class="stat-value">
            <span v-if="summaryPending" class="skeleton skeleton-text-lg" aria-hidden="true" />
            <template v-else>
              {{ dbCount }} <span class="stat-unit">database(s)</span>
            </template>
          </p>
        </div>
      </NuxtLink>
      <NuxtLink to="/settings/api-keys" class="card stat-card">
        <div class="stat-icon stat-icon-keys">
          <AppIcon name="key" :size="22" />
        </div>
        <div>
          <h2>API Keys</h2>
          <p class="stat-value">
            <span v-if="summaryPending" class="skeleton skeleton-text-lg" aria-hidden="true" />
            <template v-else>
              {{ apiKeyCount }} <span class="stat-unit">key(s)</span>
            </template>
          </p>
        </div>
      </NuxtLink>
    </div>

    <DockerStatsPanel />

    <footer class="dashboard-footer">
      <button
        type="button"
        class="btn btn-ghost btn-sm clean-btn"
        :disabled="cleanBusy || updateBusy || rebooting"
        @click="onCleanJobsClick"
      >
        <AppIcon name="broom" :size="14" />
        {{ cleanBusy ? 'Cleaning…' : 'Clean Job' }}
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-sm update-btn"
        :disabled="updateBusy || cleanBusy"
        @click="onUpdateClick"
      >
        <AppIcon name="git-pull" :size="14" />
        {{ updateBusy ? 'Updating…' : 'Update' }}
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-sm reboot-btn"
        :disabled="rebooting || cleanBusy"
        @click="onRebootClick"
      >
        <AppIcon name="power" :size="14" />
        {{ rebooting ? 'Rebooting…' : 'Reboot' }}
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
type DashboardSummary = {
  nodeSites: number
  phpSites: number
  databases: number
  apiKeys: number
}

const { data: summary, pending: summaryPending } = useFetch<DashboardSummary>(
  '/api/dashboard/summary',
  { key: 'dashboard-summary' }
)

const nodeCount = computed(() => summary.value?.nodeSites ?? 0)
const phpCount = computed(() => summary.value?.phpSites ?? 0)
const dbCount = computed(() => summary.value?.databases ?? 0)
const apiKeyCount = computed(() => summary.value?.apiKeys ?? 0)

const REBOOT_WAIT_KEY = 'dpanel-reboot-waiting'

const rebooting = ref(false)
const updateOpen = ref(false)
const updateBusy = ref(false)
const cleanBusy = ref(false)
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

async function onCleanJobsClick() {
  if (
    cleanBusy.value ||
    updateBusy.value ||
    !import.meta.client ||
    !confirm(
      'Clean stuck jobs now?\n\nThis will kill hung Update/Rebuild processes, remove locks, clear related logs, and mark running operations as failed.'
    )
  ) {
    return
  }

  cleanBusy.value = true
  clearAlert()
  updateOpen.value = false
  try {
    const res = await $fetch<{
      clearedSiteOps: number
      clearedLogs: number
      clearedSystemUpdateStatus: boolean
    }>('/api/system/clean-jobs', { method: 'POST' })
    updateBusy.value = false
    const bits = [
      res.clearedSystemUpdateStatus ? 'Update Dpanel' : null,
      res.clearedSiteOps > 0 ? `${res.clearedSiteOps} site job(s)` : null,
      res.clearedLogs > 0 ? `${res.clearedLogs} log(s)` : null
    ].filter(Boolean)
    showAlert(
      bits.length
        ? `Cleaned stuck jobs (${bits.join(', ')}). You can retry Update or Rebuild.`
        : 'Locks cleared and hung processes killed. No running jobs were marked.',
      true
    )
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not clean jobs', false)
  } finally {
    cleanBusy.value = false
  }
}

async function onUpdateClick() {
  if (
    updateBusy.value ||
    cleanBusy.value ||
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
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
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

.stat-icon-node {
  background: var(--badge-node-bg);
  color: var(--badge-node-fg);
}

.stat-icon-php {
  background: var(--badge-php-bg);
  color: var(--badge-php-fg);
}

.stat-icon-db {
  background: var(--success-muted);
  color: var(--success);
}

.stat-icon-keys {
  background: var(--warning-muted);
  color: var(--warning);
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
  min-height: 1.6em;
  display: flex;
  align-items: center;
  gap: 0.35em;
}

.stat-unit {
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--muted);
}

.dashboard-footer {
  margin-top: 2rem;
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
}

.clean-btn {
  color: var(--muted);
}

.clean-btn:hover:not(:disabled) {
  color: var(--text);
}

.update-btn {
  border-color: var(--accent);
  color: var(--accent);
}

.update-btn:hover:not(:disabled) {
  background: var(--accent-muted);
  border-color: var(--accent);
  color: var(--accent);
}

.reboot-btn {
  border-color: var(--danger);
  color: var(--danger);
}

.reboot-btn:hover:not(:disabled) {
  background: var(--danger-muted);
  border-color: var(--danger);
  color: var(--danger);
}
</style>
