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
              class="pill"
              :class="data?.installed && data?.daemonActive ? 'pill-ok' : 'pill-warn'"
            >
              {{
                data?.installed
                  ? data.daemonActive
                    ? 'Daemon active'
                    : 'Daemon inactive'
                  : 'Not installed'
              }}
            </div>
            <div v-if="data?.version" class="pill muted-pill">v{{ data.version }}</div>
            <div v-if="data?.installed" class="pill">
              freshclam: {{ data.freshclamActive ? 'active' : 'inactive' }}
            </div>
            <div v-if="scanLocked" class="pill pill-accent">Scan running</div>
          </div>

          <dl class="status-dl">
            <div>
              <dt>Installed</dt>
              <dd>{{ data?.installed ? 'Yes' : 'No' }}</dd>
            </div>
            <div>
              <dt>Daemon</dt>
              <dd>{{ data?.daemonActive ? 'Active' : data?.installed ? 'Inactive' : '—' }}</dd>
            </div>
            <div>
              <dt>freshclam</dt>
              <dd>{{ data?.freshclamActive ? 'Active' : data?.installed ? 'Inactive' : '—' }}</dd>
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
              class="btn btn-sm"
              :disabled="!data?.installed || updateBusy"
              @click="onUpdate"
            >
              {{ updateBusy ? 'Updating…' : 'Update signatures' }}
            </button>
            <button type="button" class="btn btn-ghost btn-sm" :disabled="refreshBusy" @click="load">
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
            <h2 class="section-title">Recent malware events</h2>
            <NuxtLink to="/security/events?source=clamav" class="link-sm">All events</NuxtLink>
          </div>
          <PageLoader v-if="eventsPending" label="Loading events…" />
          <ul v-else-if="recentEvents.length" class="events-list">
            <li v-for="ev in recentEvents" :key="ev.id">
              <span class="ev-time">{{ formatTime(ev.at) }}</span>
              <span>{{ ev.domain || '—' }}</span>
              <code v-if="ev.path">{{ ev.path }}</code>
            </li>
          </ul>
          <p v-else class="muted">No ClamAV events recorded yet.</p>
        </div>
      </div>

      <!-- Scan -->
      <div v-show="activeTab === 'scan'" class="tab-panel">
        <div v-if="!data?.installed" class="card muted">Install ClamAV first.</div>
        <ClamavScanPanel
          v-else
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
        <div v-if="!data?.installed" class="card muted">Install ClamAV first.</div>
        <template v-else>
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
        <div v-if="!data?.installed" class="card muted">Install ClamAV first.</div>
        <ClamavLogViewer v-else :installed="!!data?.installed" />
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

const { data: evData, pending: eventsPending } = useFetch<{ events?: SecurityEvent[] }>(
  '/api/security/events?limit=5&source=clamav',
  { key: 'clamav-recent-events' }
)
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

const tabItems = computed(() => {
  const installed = !!data.value?.installed
  return [
    { id: 'overview' as const, label: 'Overview' },
    { id: 'scan' as const, label: 'Scan', disabled: !installed },
    { id: 'results' as const, label: 'Results', disabled: !installed },
    { id: 'logs' as const, label: 'Logs', disabled: !installed },
    { id: 'guide' as const, label: 'Guide' }
  ]
})

const { startPoll, resumePollIfRunning } = useSecurityInstallPoll({
  load: () => load(true),
  data,
  installBusy,
  showAlert,
  successMessage: 'ClamAV installed'
})

async function load(silent = false) {
  if (!silent) refreshBusy.value = true
  try {
    data.value = await $fetch<ClamData>('/api/security/clamav')
  } catch (e: unknown) {
    if (!silent) {
      showAlert(e instanceof Error ? e.message : 'Could not load ClamAV', false)
    }
  } finally {
    loading.value = false
    if (!silent) refreshBusy.value = false
  }
}

async function onInstall() {
  if (!confirm('Install ClamAV on this VPS? Signature download may take several minutes.')) return
  try {
    await $fetch('/api/security/clamav/install', { method: 'POST' })
    showAlert('Installation started in the background', true)
    await load(true)
    startPoll()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Could not start install', false)
  }
}

async function onStart() {
  startBusy.value = true
  try {
    await $fetch('/api/security/clamav/start', { method: 'POST' })
    showAlert('ClamAV services started', true)
    await load(true)
  } catch (e: unknown) {
    showAlert(fetchErrorMessage(e), false)
  } finally {
    startBusy.value = false
  }
}

async function onUpdate() {
  updateBusy.value = true
  try {
    await $fetch('/api/security/clamav/update', { method: 'POST', timeout: 600_000 })
    showAlert('Signature update finished', true)
    await load()
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

function fetchErrorMessage(e: unknown): string {
  if (e && typeof e === 'object') {
    const err = e as {
      data?: { statusMessage?: string; message?: string }
      statusMessage?: string
      message?: string
    }
    if (err.data?.statusMessage) return err.data.statusMessage
    if (err.statusMessage) return err.statusMessage
    if (err.data?.message) return err.data.message
    if (err.message && !err.message.startsWith('[POST]')) return err.message
  }
  return 'Operation failed'
}

onMounted(async () => {
  await load()
  resumePollIfRunning()
  await resumeScanPoll()
})
</script>

<style scoped>
.status-card {
  margin-bottom: 1rem;
}

.status-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1rem;
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

.pill-accent {
  color: var(--accent);
}

.muted-pill {
  color: var(--muted);
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
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}

.section-title {
  margin: 0;
  font-size: 0.9375rem;
}

.link-sm {
  font-size: 0.8125rem;
  color: var(--accent);
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
