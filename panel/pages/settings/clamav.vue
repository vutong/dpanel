<template>
  <div>
    <h1>ClamAV</h1>
    <p class="page-desc">
      Scan website files under <code>apps/</code> for known malware. Daemon runs on the VPS host.
      First install may require a signature download (freshclam).
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <ClamavTabs v-model="activeTab" :tabs="tabItems" />

    <PageLoader v-if="loading" label="Loading ClamAV…" />

    <template v-else>
      <!-- Overview -->
      <div v-show="activeTab === 'overview'" class="tab-panel">
        <div class="card status-card">
          <div class="status-pills">
            <div
              v-if="data?.installed && data.daemonActive"
              class="status-active"
            >
              Daemon active
            </div>
            <div
              v-else
              class="pill"
              :class="statusPillClass"
            >
              {{ statusPillLabel }}
            </div>
            <div v-if="data?.version" class="pill muted-pill">v{{ data.version }}</div>
            <div v-if="data?.installed && data.freshclamActive" class="status-active">
              freshclam: Active
            </div>
            <div v-else-if="data?.installed" class="status-inactive">
              freshclam: Inactive
            </div>
            <div v-if="scanLocked" class="pill pill-accent">Scan running</div>
          </div>

          <dl class="status-dl">
            <div>
              <dt>Installed</dt>
              <dd>{{ installedLabel }}</dd>
            </div>
            <div>
              <dt>Daemon</dt>
              <dd>
                <span v-if="data?.daemonActive" class="status-active">Active</span>
                <span v-else-if="data?.installed" class="status-inactive">Inactive</span>
                <span v-else>—</span>
              </dd>
            </div>
            <div>
              <dt>freshclam</dt>
              <dd>
                <span v-if="data?.freshclamActive" class="status-active">Active</span>
                <span v-else-if="data?.installed" class="status-inactive">Inactive</span>
                <span v-else>—</span>
              </dd>
            </div>
            <div>
              <dt>Signatures</dt>
              <dd>{{ data?.signatureDate || '—' }}</dd>
            </div>
          </dl>

          <p
            v-if="data?.installed && (!data?.daemonActive || !data?.freshclamActive)"
            class="inactive-hint alert alert-warn"
          >
            ClamAV is installed but one or more services are <strong>not running</strong>. Click
            <strong>Start services</strong> or check the <strong>Logs</strong> tab.
          </p>

          <div class="actions">
            <button
              v-if="!data?.installed || data?.installStatus === 'running'"
              type="button"
              class="btn btn-primary"
              :disabled="installBusy || data?.installStatus === 'running'"
              @click="onInstall"
            >
              {{ installBusy || data?.installStatus === 'running' ? 'Installing…' : 'Install ClamAV' }}
            </button>
            <button
              v-if="data?.installed && (!data?.daemonActive || !data?.freshclamActive)"
              type="button"
              class="btn btn-primary"
              :disabled="startBusy"
              @click="onStart"
            >
              {{ startBusy ? 'Starting…' : 'Start services' }}
            </button>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              :disabled="!data?.installed || updateBusy"
              @click="onUpdate"
            >
              {{ updateBusy ? 'Updating…' : 'Update signatures' }}
            </button>
            <button type="button" class="btn btn-ghost btn-sm" :disabled="refreshBusy" @click="refreshAll">
              <AppIcon name="refresh" :size="14" />
              Refresh
            </button>
          </div>
          <p v-if="data?.installStatus === 'running'" class="install-hint muted">
            Installation runs in the background (signature download may take several minutes). This page
            refreshes every 5 seconds.
          </p>
        </div>

        <div class="card section">
          <div class="section-head">
            <h2 class="section-title">Recent ClamAV events</h2>
            <div class="events-filters">
              <label class="field-inline">
                <span class="label-sm">
                  Count
                  <span
                    class="hint-icon"
                    title="Allows displaying up to 350 results"
                    aria-label="Allows displaying up to 350 results"
                  >
                    <AppIcon name="info" :size="12" />
                  </span>
                </span>
                <select v-model.number="eventsLimit" class="select select-sm">
                  <option :value="25">25</option>
                  <option :value="50">50</option>
                  <option :value="100">100</option>
                  <option :value="200">200</option>
                  <option :value="350">350</option>
                </select>
              </label>
              <label class="field-inline">
                <span class="label-sm">Date</span>
                <select v-model="eventsDateRange" class="select select-sm">
                  <option value="all">All</option>
                  <option value="today">Today</option>
                  <option value="7d">7 days</option>
                  <option value="30d">30 days</option>
                </select>
              </label>
              <label class="field-inline">
                <span class="label-sm">Website</span>
                <select v-model="eventsWebsiteFilter" class="select select-sm events-website">
                  <option value="">All</option>
                  <option v-for="s in sites" :key="s.domain" :value="s.domain">
                    {{ s.domain }}
                  </option>
                </select>
              </label>
            </div>
          </div>
          <PageLoader v-if="eventsPending" label="Loading events…" />
          <ul v-else-if="recentEvents.length" class="events-list">
            <li v-for="ev in recentEvents" :key="ev.id">
              <span class="ev-time">{{ formatTime(ev.at) }}</span>
              <span>{{ ev.domain || '—' }}</span>
              <code v-if="ev.path">{{ ev.path }}</code>
            </li>
          </ul>
          <p v-else class="muted">
            {{
              eventsWebsiteFilter || eventsDateRange !== 'all'
                ? 'No events match the current filters.'
                : 'No ClamAV events recorded yet.'
            }}
          </p>
        </div>
      </div>

      <!-- Scan -->
      <div v-show="activeTab === 'scan'" class="tab-panel">
        <div v-if="!isInstalled" class="card muted">Install ClamAV first.</div>
        <ClamavScanPanel
          v-else-if="activeTab === 'scan'"
          :installed="!!data?.installed"
          :sites="sites"
          :scan-locked="scanLocked"
          :scan-busy="scanBusy"
          :polling="scanPolling"
          :active-target="activeScan?.target"
          @scan-all="onScanAll"
          @scan-site="onScanSite"
        />
      </div>

      <!-- Results -->
      <div v-show="activeTab === 'results'" class="tab-panel">
        <div v-if="!isInstalled" class="card muted">Install ClamAV first.</div>
        <template v-else-if="activeTab === 'results'">
          <ClamavScanHistory
            ref="historyRef"
            :sites="sites"
            :selected-id="selectedScanId"
            @select="onSelectScan"
          />
          <ClamavResultsPanel :scan-id="selectedScanId" />
        </template>
      </div>

      <!-- Logs -->
      <div v-show="activeTab === 'logs'" class="tab-panel">
        <div v-if="!isInstalled" class="card muted">Install ClamAV first.</div>
        <ClamavLogViewer v-else-if="activeTab === 'logs'" :installed="!!data?.installed" />
      </div>

      <!-- Guide -->
      <div v-show="activeTab === 'guide'" class="tab-panel">
        <ClamavGuide />
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import ClamavTabs, { type ClamavTabId } from '~/components/clamav/ClamavTabs.vue'
import type { ClamavScanSummary } from '~/composables/useClamavScan'

type ClamData = {
  ok?: boolean
  error?: string
  installed?: boolean
  daemonActive?: boolean
  freshclamActive?: boolean
  signatureDate?: string | null
  version?: string | null
  installStatus?: 'none' | 'running' | 'ok' | 'error'
  installMessage?: string
  activeScan?: ClamavScanSummary | null
}

type SecurityEvent = {
  id: string
  at: string
  domain?: string | null
  path?: string | null
}

const route = useRoute()
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

const { data: sitesData } = useFetch<{ sites?: { domain: string }[] }>('/api/websites')
const sites = computed(() => sitesData.value?.sites ?? [])

const data = ref<ClamData | null>(null)
const loading = ref(true)
const installBusy = ref(false)
const updateBusy = ref(false)
const startBusy = ref(false)
const refreshBusy = ref(false)
const scanBusy = ref(false)
const selectedScanId = ref<string | null>(null)
const historyRef = ref<{ refresh?: () => void } | null>(null)

const activeTab = ref<ClamavTabId>(
  (['overview', 'scan', 'results', 'logs', 'guide'].includes(String(route.query.tab))
    ? String(route.query.tab)
    : 'overview') as ClamavTabId
)

const eventsLimit = ref(25)
const eventsDateRange = ref<'all' | 'today' | '7d' | '30d'>('all')
const eventsWebsiteFilter = ref('')

function eventsSinceIso(range: typeof eventsDateRange.value): string | null {
  if (range === 'all') return null
  const now = new Date()
  if (range === 'today') {
    const start = new Date(now)
    start.setHours(0, 0, 0, 0)
    return start.toISOString()
  }
  const days = range === '7d' ? 7 : 30
  return new Date(now.getTime() - days * 24 * 60 * 60 * 1000).toISOString()
}

const eventsUrl = computed(() => {
  const q = new URLSearchParams({
    source: 'clamav',
    limit: String(eventsLimit.value)
  })
  const since = eventsSinceIso(eventsDateRange.value)
  if (since) q.set('since', since)
  if (eventsWebsiteFilter.value) q.set('domain', eventsWebsiteFilter.value)
  return `/api/security/events?${q}`
})

const { data: evData, pending: eventsPending } = useFetch<{ events?: SecurityEvent[] }>(eventsUrl, {
  key: 'clamav-recent-events',
  watch: [eventsUrl]
})

const recentEvents = computed(() => evData.value?.events ?? [])

const {
  activeScan,
  polling: scanPolling,
  startScan,
  resumePollIfRunning: resumeScanPoll
} = useClamavScan({
  showAlert,
  onComplete: (scan) => {
    void load(true)
    historyRef.value?.refresh?.()
    selectedScanId.value = scan.id
  }
})

const scanLocked = computed(
  () => scanPolling.value || activeScan.value?.status === 'running' || !!data.value?.activeScan
)

const isInstalled = computed(() => data.value?.installed === true)

const statusPillLabel = computed(() => {
  if (data.value?.installed === true) {
    return data.value.daemonActive ? 'Daemon active' : 'Daemon inactive'
  }
  if (data.value?.installed === false) return 'Not installed'
  if (data.value?.ok === false) return 'Status unavailable'
  return '—'
})

const statusPillClass = computed(() => {
  if (data.value?.installed === true && data.value.daemonActive) return 'pill-ok'
  return 'pill-warn'
})

const installedLabel = computed(() => {
  if (data.value?.installed === true) return 'Yes'
  if (data.value?.installed === false) return 'No'
  return '—'
})

const tabItems = computed(() => {
  const installed = isInstalled.value
  return [
    { id: 'overview' as const, label: 'Overview' },
    { id: 'scan' as const, label: 'Scan', disabled: !installed },
    { id: 'results' as const, label: 'Results', disabled: !installed },
    { id: 'logs' as const, label: 'Logs', disabled: !installed },
    { id: 'guide' as const, label: 'Guide' }
  ]
})

const { startPoll, resumePollIfRunning } = useSecurityInstallPoll({
  load: () => refreshAll(true),
  data,
  installBusy,
  showAlert,
  successMessage: 'ClamAV installed'
})

async function loadSummary(silent = false) {
  if (!silent) refreshBusy.value = true
  const prev = data.value
  try {
    const res = await $fetch<ClamData>('/api/security/clamav')
    if (res.ok === false) {
      if (prev?.installed === true) {
        data.value = {
          ...prev,
          ok: false,
          error: res.error,
          installStatus: res.installStatus ?? prev.installStatus,
          installMessage: res.installMessage ?? prev.installMessage,
          activeScan: res.activeScan ?? prev.activeScan
        }
      } else {
        data.value = res
      }
      if (res.error && !silent) showAlert(res.error, false)
      return
    }
    data.value = res
  } catch (e: unknown) {
    if (!silent) {
      showAlert(fetchApiErrorMessage(e, 'Could not load ClamAV'), false)
    }
  } finally {
    loading.value = false
    if (!silent) refreshBusy.value = false
  }
}

async function refreshAll(silent = false) {
  await loadSummary(silent)
  if (activeTab.value === 'results') {
    historyRef.value?.refresh?.()
  }
}

async function load(silent = false) {
  await refreshAll(silent)
}

async function onInstall() {
  if (!confirm('Install ClamAV on this VPS? Signature download may take several minutes.')) return
  try {
    await $fetch('/api/security/clamav/install', { method: 'POST' })
    showAlert('Installation started in the background', true)
    await loadSummary(true)
    startPoll()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Could not start install', false)
  }
}

async function onStart() {
  startBusy.value = true
  try {
    const res = await $fetch<{ ok?: boolean; error?: string }>('/api/security/clamav/start', {
      method: 'POST'
    })
    if (res.ok === false) {
      showAlert(res.error || 'Start failed', false)
      return
    }
    showAlert('ClamAV services started', true)
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(fetchApiErrorMessage(e), false)
  } finally {
    startBusy.value = false
  }
}

async function onUpdate() {
  updateBusy.value = true
  try {
    const res = await $fetch<{ ok?: boolean; error?: string }>('/api/security/clamav/update', {
      method: 'POST',
      timeout: 600_000
    })
    if (res.ok === false) {
      showAlert(res.error || 'Update failed', false)
      return
    }
    showAlert('Signature update finished', true)
    await refreshAll()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Update failed', false)
  } finally {
    updateBusy.value = false
  }
}

async function onScanAll() {
  if (!confirm('Scan all files under apps/? This may take a long time on large sites.')) return
  scanBusy.value = true
  try {
    await startScan()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Could not start scan', false)
  } finally {
    scanBusy.value = false
  }
}

async function onScanSite(domain: string) {
  scanBusy.value = true
  try {
    await startScan({ domain })
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Could not start scan', false)
  } finally {
    scanBusy.value = false
  }
}

function onSelectScan(id: string) {
  selectedScanId.value = id
}

function formatTime(iso: string) {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

onMounted(async () => {
  await loadSummary()
  resumePollIfRunning()
  await resumeScanPoll()
})
</script>

<style scoped>
.page-desc {
  color: var(--muted);
  margin: 0.35rem 0 1.25rem;
  max-width: 52rem;
  line-height: 1.45;
  font-size: 0.92rem;
}

.page-desc code {
  font-size: 0.85em;
}

.status-card {
  margin-bottom: 1rem;
}

.status-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.status-dl {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 0.75rem 1.5rem;
  margin: 0 0 1rem;
}

.status-dl dt {
  font-size: 0.75rem;
  color: var(--muted);
  margin-bottom: 0.125rem;
}

.status-dl dd {
  margin: 0;
  font-weight: 600;
}

.inactive-hint {
  margin: 0 0 1rem;
  font-size: 0.875rem;
  line-height: 1.5;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.section {
  margin-bottom: 1rem;
}

.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}

.section-title {
  margin: 0;
  font-size: 0.9375rem;
}

.events-filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
}

.field-inline {
  display: flex;
  align-items: center;
  gap: 0.375rem;
}

.label-sm {
  font-size: 0.8125rem;
  color: var(--muted);
  white-space: nowrap;
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
}

.hint-icon {
  display: inline-flex;
  color: var(--muted);
  cursor: help;
  opacity: 0.85;
}

.hint-icon:hover {
  opacity: 1;
  color: var(--text);
}

.events-website {
  min-width: 10rem;
  max-width: 14rem;
}

.events-list {
  list-style: none;
  margin: 0;
  padding: 0;
  font-size: 0.8125rem;
}

.events-list li {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  padding: 0.35rem 0;
  border-bottom: 1px solid var(--border);
}

.ev-time {
  color: var(--muted);
  min-width: 8rem;
}

.install-hint {
  margin: 0.75rem 0 0;
  font-size: 0.8125rem;
}

.muted {
  color: var(--muted);
}

.tab-panel {
  min-height: 120px;
}
</style>
