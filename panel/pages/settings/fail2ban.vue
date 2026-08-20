<template>
  <div>
    <h1>Fail2ban</h1>
    <p class="page-desc">
      Ban IPs after repeated SSH failures, panel login failures, or exploit scans. Runs on the VPS host
      (not inside Docker).
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <Fail2banTabs v-model="activeTab" :tabs="tabItems" />

    <PageLoader v-if="loading" label="Loading Fail2ban…" />

    <template v-else>
      <!-- Overview -->
      <div v-show="activeTab === 'overview'" class="tab-panel">
        <div class="card status-card">
          <div class="status-pills">
            <div class="pill" :class="data?.installed && data?.active ? 'pill-ok' : 'pill-warn'">
              {{ data?.installed ? (data.active ? 'Active' : 'Inactive') : 'Not installed' }}
            </div>
            <div v-if="data?.version" class="pill muted-pill">v{{ data.version }}</div>
            <div class="pill">{{ jailCount }} jail(s)</div>
            <div class="pill">{{ bannedCount }} banned</div>
            <div class="pill">{{ failedCount }} currently failed</div>
          </div>

          <dl class="status-dl">
            <div>
              <dt>Installed</dt>
              <dd>{{ data?.installed ? 'Yes' : 'No' }}</dd>
            </div>
            <div>
              <dt>Service</dt>
              <dd>{{ data?.active ? 'Active' : data?.installed ? 'Inactive' : '—' }}</dd>
            </div>
            <div>
              <dt>Banned IPs</dt>
              <dd>{{ bannedCount }}</dd>
            </div>
          </dl>

          <p v-if="data?.installed && !data?.active" class="inactive-hint alert alert-warn">
            Fail2ban is installed but the service is <strong>not running</strong>. Bans are not active.
            Click <strong>Start service</strong> — if it fails, check the <strong>Logs</strong> tab or fix jail
            config under <strong>Jails &amp; Settings</strong> (invalid config prevents start).
          </p>

          <div class="actions">
            <button
              v-if="!data?.installed || data?.installStatus === 'running'"
              type="button"
              class="btn btn-primary"
              :disabled="installBusy || data?.installStatus === 'running'"
              @click="onInstall"
            >
              {{ installBusy || data?.installStatus === 'running' ? 'Installing…' : 'Install Fail2ban' }}
            </button>
            <button
              v-if="data?.installed && !data?.active"
              type="button"
              class="btn btn-primary"
              :disabled="startBusy"
              @click="onStart"
            >
              {{ startBusy ? 'Starting…' : 'Start service' }}
            </button>
            <button
              type="button"
              class="btn btn-sm"
              :disabled="!data?.installed || reloadBusy"
              @click="onReload"
            >
              {{ reloadBusy ? 'Reloading…' : 'Reload service' }}
            </button>
            <button
              v-if="data?.clientIp && data?.installed"
              type="button"
              class="btn btn-ghost btn-sm"
              @click="unban(data.clientIp!)"
            >
              Unban my IP
            </button>
            <button type="button" class="btn btn-ghost btn-sm" :disabled="refreshBusy" @click="refreshAll">
              <AppIcon name="refresh" :size="14" />
              Refresh
            </button>
          </div>
          <p v-if="data?.installStatus === 'running'" class="install-hint muted">
            Installation runs in the background. This page refreshes every 5 seconds.
          </p>
        </div>

        <div class="card section">
          <div class="section-head">
            <h2 class="section-title">Recent Fail2ban events</h2>
            <NuxtLink to="/security/events?source=fail2ban" class="link-sm">All events</NuxtLink>
          </div>
          <PageLoader v-if="eventsPending" label="Loading events…" />
          <ul v-else-if="recentEvents.length" class="events-list">
            <li v-for="ev in recentEvents" :key="ev.id">
              <span class="ev-time">{{ formatTime(ev.at) }}</span>
              <span>{{ ev.ip || '—' }}</span>
              <span class="muted">{{ ev.detail || '' }}</span>
            </li>
          </ul>
          <p v-else class="muted">No Fail2ban events recorded yet.</p>
        </div>
      </div>

      <!-- Jails & Settings -->
      <div v-show="activeTab === 'jails'" class="tab-panel">
        <div v-if="!data?.installed" class="card muted">Install Fail2ban first.</div>
        <PageLoader v-else-if="jailsLoading" label="Loading jails…" />
        <Fail2banJailForm
          v-else
          :settings="data.settings ?? { ignoreip: ['127.0.0.1/8', '::1'], jails: {} }"
          :jails="jailsForForm"
          :installed="!!data?.installed"
          :client-ip="data?.clientIp"
          :saving="saveBusy"
          :on-save="onSaveSettings"
          @reset-jail="onResetJail"
        />
      </div>

      <!-- Banned IPs -->
      <div v-show="activeTab === 'banned'" class="tab-panel">
        <div v-if="!data?.installed" class="card muted">Install Fail2ban first.</div>
        <PageLoader v-else-if="bannedLoading" label="Loading banned IPs…" />
        <Fail2banBannedTable
          v-else
          :jails="bannedJails"
          :banned-ips="bannedIpsList"
          :ip-geo="bannedIpGeo"
          :geoip="bannedGeoip"
          :sync-busy="syncGeoBusy"
          @unban="unban"
          @sync-geoip="onSyncGeoip"
        />
      </div>

      <!-- Logs -->
      <div v-show="activeTab === 'logs'" class="tab-panel">
        <div v-if="!data?.installed" class="card muted">Install Fail2ban first.</div>
        <Fail2banLogViewer v-else :installed="!!data?.installed" :active="!!data?.active" />
      </div>

      <!-- Guide -->
      <div v-show="activeTab === 'guide'" class="tab-panel">
        <Fail2banGuide />
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import Fail2banTabs, { type Fail2banTabId } from '~/components/fail2ban/Fail2banTabs.vue'

type JailSettings = {
  enabled: boolean
  maxretry: number
  findtime: number
  bantime: number
}

type JailRow = {
  name: string
  managedBy?: 'dpanel' | 'system'
  enabled?: boolean
  filter?: string | null
  logpath?: string | null
  maxretry?: number
  findtime?: number
  bantime?: number
  currentlyFailed?: number
  totalFailed?: number
  totalBanned?: number
  bannedIps?: { ip: string; bannedAt: string | null }[]
}

type Fail2banSummary = {
  ok?: boolean
  error?: string
  installed?: boolean
  active?: boolean
  version?: string | null
  jails?: JailRow[]
  bannedIps?: string[]
  settings?: { ignoreip: string[]; jails: Record<string, JailSettings> }
  clientIp?: string | null
  installStatus?: 'none' | 'running' | 'ok' | 'error'
  installMessage?: string
}

type Fail2banJailsPayload = {
  jails?: JailRow[]
  global?: { ignoreip: string[] }
  settings?: Fail2banSummary['settings']
}

type Fail2banBannedPayload = {
  jails?: JailRow[]
  bannedIps?: string[]
  ipGeo?: Record<
    string,
    { countryCode: string | null; countryName: string | null; flag: string }
  >
  geoip?: {
    ready: boolean
    syncedAt: string | null
    buildDate?: string | null
    edition?: string | null
  }
}

type SecurityEvent = {
  id: string
  at: string
  ip?: string | null
  detail?: string | null
}

const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

const data = ref<Fail2banSummary | null>(null)
const jailsDetail = ref<JailRow[] | null>(null)
const bannedPayload = ref<Fail2banBannedPayload | null>(null)

const loading = ref(true)
const jailsLoading = ref(false)
const bannedLoading = ref(false)
const jailsLoaded = ref(false)
const bannedLoaded = ref(false)

const installBusy = ref(false)
const refreshBusy = ref(false)
const reloadBusy = ref(false)
const startBusy = ref(false)
const saveBusy = ref(false)
const syncGeoBusy = ref(false)
const activeTab = ref<Fail2banTabId>('overview')

const { data: evData, pending: eventsPending } = useFetch<{ events?: SecurityEvent[] }>(
  '/api/security/events?limit=5&source=fail2ban',
  { key: 'fail2ban-recent-events' }
)

const recentEvents = computed(() => evData.value?.events ?? [])

const tabItems = computed(() => {
  const installed = !!data.value?.installed
  return [
    { id: 'overview' as const, label: 'Overview' },
    { id: 'jails' as const, label: 'Jails & Settings', disabled: !installed },
    { id: 'banned' as const, label: 'Banned IPs', disabled: !installed },
    { id: 'logs' as const, label: 'Logs', disabled: !installed },
    { id: 'guide' as const, label: 'Guide' }
  ]
})

const jailCount = computed(() => data.value?.jails?.length ?? 0)
const bannedCount = computed(() => data.value?.bannedIps?.length ?? 0)
const failedCount = computed(() =>
  (data.value?.jails || []).reduce((n, j) => n + (j.currentlyFailed || 0), 0)
)

const jailsForForm = computed(() => jailsDetail.value ?? data.value?.jails ?? [])
const bannedJails = computed(() => bannedPayload.value?.jails ?? [])
const bannedIpsList = computed(() => bannedPayload.value?.bannedIps ?? data.value?.bannedIps ?? [])
const bannedIpGeo = computed(() => bannedPayload.value?.ipGeo ?? {})
const bannedGeoip = computed(() => bannedPayload.value?.geoip ?? null)

const { startPoll, resumePollIfRunning } = useSecurityInstallPoll({
  load: () => refreshAll(true),
  data,
  installBusy,
  showAlert,
  successMessage: 'Fail2ban installed'
})

function invalidateTabData() {
  jailsLoaded.value = false
  bannedLoaded.value = false
  jailsDetail.value = null
  bannedPayload.value = null
}

async function loadSummary(silent = false) {
  if (!silent) refreshBusy.value = true
  try {
    const res = await $fetch<Fail2banSummary>('/api/security/fail2ban')
    data.value = res
    invalidateTabData()
    if (res.ok === false && res.error && !silent) {
      showAlert(res.error, false)
    }
  } catch (e: unknown) {
    if (!silent) {
      showAlert(e instanceof Error ? e.message : 'Could not load Fail2ban', false)
    }
  } finally {
    loading.value = false
    if (!silent) refreshBusy.value = false
  }
}

async function loadJails(silent = false) {
  if (!data.value?.installed || jailsLoading.value) return
  jailsLoading.value = true
  try {
    const res = await $fetch<Fail2banJailsPayload>('/api/security/fail2ban/jails')
    jailsDetail.value = res.jails ?? []
    if (res.settings) data.value = { ...data.value, settings: res.settings }
    jailsLoaded.value = true
  } catch (e: unknown) {
    if (!silent) showAlert(fetchErrorMessage(e), false)
  } finally {
    jailsLoading.value = false
  }
}

async function loadBanned(silent = false) {
  if (!data.value?.installed || bannedLoading.value) return
  bannedLoading.value = true
  try {
    bannedPayload.value = await $fetch<Fail2banBannedPayload>('/api/security/fail2ban/banned')
    bannedLoaded.value = true
  } catch (e: unknown) {
    if (!silent) showAlert(fetchErrorMessage(e), false)
  } finally {
    bannedLoading.value = false
  }
}

async function refreshAll(silent = false) {
  await loadSummary(silent)
  if (activeTab.value === 'jails' && data.value?.installed) {
    await loadJails(silent)
  }
  if (activeTab.value === 'banned' && data.value?.installed) {
    await loadBanned(silent)
  }
}

watch(activeTab, (tab) => {
  if (!data.value?.installed || loading.value) return
  if (tab === 'jails' && !jailsLoaded.value) void loadJails(true)
  if (tab === 'banned' && !bannedLoaded.value) void loadBanned(true)
})

async function onInstall() {
  if (!confirm('Install Fail2ban on this VPS?')) return
  try {
    await $fetch('/api/security/fail2ban/install', { method: 'POST' })
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
    await $fetch('/api/security/fail2ban/start', { method: 'POST' })
    showAlert('Fail2ban service started', true)
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(fetchErrorMessage(e), false)
  } finally {
    startBusy.value = false
  }
}

async function onReload() {
  reloadBusy.value = true
  try {
    await $fetch('/api/security/fail2ban/reload', { method: 'POST' })
    showAlert('Fail2ban reloaded', true)
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Reload failed', false)
  } finally {
    reloadBusy.value = false
  }
}

async function unban(ip: string) {
  if (!confirm(`Unban ${ip}?`)) return
  try {
    await $fetch('/api/security/fail2ban/unban', { method: 'POST', body: { ip } })
    showAlert(`Unbanned ${ip}`, true)
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Unban failed', false)
  }
}

async function onSyncGeoip() {
  syncGeoBusy.value = true
  try {
    const res = await $fetch<{ ok?: boolean; syncedAt?: string }>('/api/security/geoip/sync', {
      method: 'POST'
    })
    showAlert(
      res.syncedAt
        ? `Country database synced (${new Date(res.syncedAt).toLocaleString()})`
        : 'Country database synced',
      true
    )
    bannedLoaded.value = false
    await loadBanned(true)
  } catch (e: unknown) {
    showAlert(fetchErrorMessage(e), false)
  } finally {
    syncGeoBusy.value = false
  }
}

async function onSaveSettings(settings: {
  ignoreip: string[]
  jails: Record<string, JailSettings>
}): Promise<{ ok: boolean; message: string }> {
  saveBusy.value = true
  try {
    const res = await $fetch<{ settings: typeof settings; warnings?: string[] }>(
      '/api/security/fail2ban/settings',
      { method: 'PUT', body: settings }
    )
    data.value = { ...data.value, settings: res.settings }
    const warn = res.warnings?.length ? ` (${res.warnings.join('; ')})` : ''
    const message = `Settings applied${warn}`
    showAlert(message, true)
    jailsLoaded.value = false
    await refreshAll(true)
    return { ok: true, message }
  } catch (e: unknown) {
    const message = fetchErrorMessage(e)
    showAlert(message, false)
    return { ok: false, message }
  } finally {
    saveBusy.value = false
  }
}

async function onResetJail(jail: string) {
  if (!confirm(`Reset ${jail} to default settings?`)) return
  saveBusy.value = true
  try {
    const res = await $fetch<{ settings: Fail2banSummary['settings'] }>(
      '/api/security/fail2ban/settings',
      { method: 'PUT', body: { resetJail: jail } }
    )
    if (res.settings) data.value = { ...data.value, settings: res.settings }
    showAlert(`${jail} reset to defaults`, true)
    jailsLoaded.value = false
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Reset failed', false)
  } finally {
    saveBusy.value = false
  }
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
    if (err.message && !err.message.startsWith('[PUT]')) return err.message
  }
  return 'Request failed'
}

onMounted(async () => {
  await loadSummary()
  resumePollIfRunning()
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

.inactive-hint {
  margin: 0 0 1rem;
  font-size: 0.875rem;
  line-height: 1.5;
}

.muted {
  color: var(--muted);
}

.tab-panel {
  min-height: 120px;
}
</style>
