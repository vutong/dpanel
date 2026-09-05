<template>
  <div>
    <h1>Fail2ban</h1>
    <p class="page-desc">
      Ban IPs after repeated SSH failures, panel login failures, or exploit scans. Runs on the VPS host
      (not inside Docker).
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <Fail2banTabs v-model="activeTab" :tabs="tabItems" />

    <!-- Overview -->
    <div v-show="activeTab === 'overview'" class="tab-panel">
      <div class="card status-card">
        <template v-if="loading">
          <dl class="status-dl" aria-hidden="true">
            <div v-for="n in 6" :key="n">
              <span class="skeleton skeleton-line-sm" style="width: 3rem; margin-bottom: 0.35rem" />
              <span class="skeleton skeleton-text-lg" style="width: 2.5rem" />
            </div>
          </dl>
          <div class="actions" aria-hidden="true">
            <span class="skeleton skeleton-text" style="width: 7rem; height: 1.75rem" />
            <span class="skeleton skeleton-text" style="width: 5.5rem; height: 1.75rem" />
            <span class="skeleton skeleton-text" style="width: 4.5rem; height: 1.75rem" />
          </div>
        </template>
        <template v-else>
          <div v-if="showStatusPills" class="status-pills">
            <div class="pill" :class="statusPillClass">
              {{ statusPillLabel }}
            </div>
          </div>

          <dl class="status-dl">
            <div>
              <dt>Installed</dt>
              <dd>{{ installedLabel }}</dd>
            </div>
            <div>
              <dt>Service</dt>
              <dd>
                <span v-if="data?.active" class="status-active">Active</span>
                <span v-else-if="data?.installed" class="status-inactive">Inactive</span>
                <span v-else>—</span>
              </dd>
            </div>
            <div>
              <dt>Jail(s)</dt>
              <dd>{{ jailCount }}</dd>
            </div>
            <div>
              <dt>Banned</dt>
              <dd>{{ bannedCount }}</dd>
            </div>
            <div>
              <dt>Suspected</dt>
              <dd>{{ failedCount }}</dd>
            </div>
            <div>
              <dt>Version</dt>
              <dd>{{ data?.version ? `v${data.version}` : '—' }}</dd>
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
              class="btn btn-ghost btn-sm"
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
        </template>
      </div>

      <div class="card section">
        <div class="section-head">
          <h2 class="section-title">Recent Fail2ban events</h2>
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
              <span class="label-sm">IP</span>
              <input
                v-model.trim="eventsIpFilter"
                type="search"
                class="input input-sm events-ip"
                placeholder="Filter IP…"
              />
            </label>
          </div>
        </div>
        <div v-if="eventsPending" aria-hidden="true">
          <div v-for="n in 5" :key="n" class="skeleton-row" style="padding: 0.35rem 0; margin-bottom: 0">
            <span class="skeleton skeleton-line" style="width: 8rem" />
            <span class="skeleton skeleton-line" style="width: 6rem" />
            <span class="skeleton skeleton-line" style="width: 40%" />
          </div>
        </div>
        <ul v-else-if="recentEvents.length" class="events-list">
          <li v-for="ev in recentEvents" :key="ev.id">
            <span class="ev-time">{{ formatTime(ev.at) }}</span>
            <span>{{ ev.ip || '—' }}</span>
            <span class="muted">{{ ev.detail || '' }}</span>
          </li>
        </ul>
        <p v-else class="muted">
          {{
            eventsIpFilter || eventsDateRange !== 'all'
              ? 'No events match the current filters.'
              : 'No Fail2ban events recorded yet.'
          }}
        </p>
      </div>
    </div>

    <!-- Jails & Settings -->
    <div v-show="activeTab === 'jails'" class="tab-panel">
      <div v-if="!isInstalled && !loading" class="card muted">Install Fail2ban first.</div>
      <div v-else-if="jailsError" class="card muted warn">{{ jailsError }}</div>
      <div
        v-else-if="loading || jailsLoading || !jailsLoaded"
        class="card"
        aria-hidden="true"
      >
        <span class="skeleton skeleton-line" style="width: 30%; margin-bottom: 1rem" />
        <span class="skeleton skeleton-block" style="height: 3.5rem; margin-bottom: 1rem" />
        <div class="skeleton-row">
          <span class="skeleton skeleton-line" style="width: 35%" />
          <span class="skeleton skeleton-line" style="width: 20%" />
        </div>
        <div class="skeleton-row">
          <span class="skeleton skeleton-line" style="width: 40%" />
          <span class="skeleton skeleton-line" style="width: 18%" />
        </div>
        <div class="skeleton-row">
          <span class="skeleton skeleton-line" style="width: 28%" />
          <span class="skeleton skeleton-line" style="width: 22%" />
        </div>
        <span class="skeleton skeleton-block" style="height: 5rem; margin-top: 0.5rem" />
      </div>
      <Fail2banJailForm
        v-else
        :settings="data?.settings ?? { ignoreip: ['127.0.0.1/8', '::1'], jails: {} }"
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
      <div v-if="!isInstalled && !loading" class="card muted">Install Fail2ban first.</div>
      <div v-else-if="!bannedLoaded && bannedError" class="card muted warn">{{ bannedError }}</div>
      <div
        v-else-if="loading || bannedLoading || !bannedLoaded"
        class="card"
        aria-hidden="true"
      >
        <div v-for="n in 6" :key="n" class="skeleton-row" style="padding: 0.4rem 0; margin-bottom: 0">
          <span class="skeleton skeleton-line" style="width: 22%" />
          <span class="skeleton skeleton-line" style="width: 18%" />
          <span class="skeleton skeleton-line" style="width: 14%" />
          <span class="skeleton skeleton-line" style="width: 12%" />
        </div>
      </div>
      <Fail2banBannedTable
        v-else-if="bannedLoaded"
        :jails="bannedJails"
        :banned-ips="bannedIpsList"
        :ip-geo="bannedIpGeo"
        :geoip="bannedGeoip"
        :sync-busy="syncGeoBusy"
        :refreshing="bannedLoading"
        @unban="unban"
        @sync-geoip="onSyncGeoip"
        @refresh="loadBanned(true)"
      />
    </div>

    <!-- Logs -->
    <div v-show="activeTab === 'logs'" class="tab-panel">
      <div v-if="!data?.installed && !loading" class="card muted">Install Fail2ban first.</div>
      <Fail2banLogViewer
        v-else-if="data?.installed"
        :installed="!!data?.installed"
        :active="!!data?.active"
      />
    </div>

    <!-- Guide -->
    <div v-show="activeTab === 'guide'" class="tab-panel">
      <Fail2banGuide />
    </div>
  </div>
</template>

<script setup lang="ts">
import Fail2banTabs, { type Fail2banTabId } from '~/components/fail2ban/Fail2banTabs.vue'

type JailSettings = {
  enabled: boolean
  maxretry: number
  findtime: number
  bantime: number
  bantimeIncrement?: boolean
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
  ok?: boolean
  error?: string
  jails?: JailRow[]
  global?: { ignoreip: string[] }
  settings?: Fail2banSummary['settings']
}

type Fail2banBannedPayload = {
  ok?: boolean
  error?: string
  jails?: JailRow[]
  bannedIps?: string[]
  ipGeo?: Record<
    string,
    { countryCode: string | null; countryName: string | null; flag: string }
  >
  geoip?: {
    ready: boolean
    syncedAt: string | null
    provider?: string | null
    count?: number
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
const jailsError = ref('')
const bannedError = ref('')

const installBusy = ref(false)
const refreshBusy = ref(false)
const reloadBusy = ref(false)
const startBusy = ref(false)
const saveBusy = ref(false)
const syncGeoBusy = ref(false)
const activeTab = ref<Fail2banTabId>('overview')

const eventsLimit = ref(25)
const eventsDateRange = ref<'all' | 'today' | '7d' | '30d'>('all')
const eventsIpFilter = ref('')
const eventsIpQuery = ref('')

let eventsIpTimer: ReturnType<typeof setTimeout> | null = null
watch(eventsIpFilter, (value) => {
  if (eventsIpTimer) clearTimeout(eventsIpTimer)
  eventsIpTimer = setTimeout(() => {
    eventsIpQuery.value = value
  }, 300)
})

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
    source: 'fail2ban',
    limit: String(eventsLimit.value)
  })
  const since = eventsSinceIso(eventsDateRange.value)
  if (since) q.set('since', since)
  if (eventsIpQuery.value) q.set('ip', eventsIpQuery.value)
  return `/api/security/events?${q}`
})

const { data: evData, pending: eventsPending } = useFetch<{ events?: SecurityEvent[] }>(eventsUrl, {
  key: 'fail2ban-recent-events',
  watch: [eventsUrl]
})

const recentEvents = computed(() => evData.value?.events ?? [])

const isInstalled = computed(() => data.value?.installed === true)

const statusPillLabel = computed(() => {
  if (data.value?.installed === false) return 'Not installed'
  if (data.value?.ok === false) return 'Status unavailable'
  return '—'
})

const statusPillClass = computed(() => 'pill-warn')

const showStatusPills = computed(
  () => data.value?.installed === false || data.value?.ok === false
)

const installedLabel = computed(() => {
  if (data.value?.installed === true) return 'Yes'
  if (data.value?.installed === false) return 'No'
  return '—'
})

const tabItems = computed(() => {
  const installed = isInstalled.value
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
  jailsError.value = ''
  bannedError.value = ''
  jailsDetail.value = null
  bannedPayload.value = null
}

async function loadSummary(silent = false) {
  if (!silent) {
    loading.value = true
    refreshBusy.value = true
  }
  const prev = data.value
  try {
    const res = await $fetch<Fail2banSummary>('/api/security/fail2ban')
    if (res.ok === false) {
      if (prev?.installed === true) {
        data.value = {
          ...prev,
          ok: false,
          error: res.error,
          installStatus: res.installStatus ?? prev.installStatus,
          installMessage: res.installMessage ?? prev.installMessage
        }
      } else {
        data.value = res
      }
      if (res.error && !silent) showAlert(res.error, false)
      return
    }
    data.value = res
    invalidateTabData()
  } catch (e: unknown) {
    if (!silent) {
      showAlert(fetchApiErrorMessage(e, 'Could not load Fail2ban'), false)
    }
  } finally {
    loading.value = false
    if (!silent) refreshBusy.value = false
  }
}

async function loadJails(silent = false) {
  if (!isInstalled.value || jailsLoading.value) return
  jailsLoading.value = true
  jailsError.value = ''
  try {
    const res = await $fetch<Fail2banJailsPayload>('/api/security/fail2ban/jails')
    if (res.ok === false) {
      jailsError.value = res.error || 'Could not load jails'
      if (!silent) showAlert(jailsError.value, false)
      return
    }
    jailsDetail.value = res.jails ?? []
    if (res.settings && data.value) data.value = { ...data.value, settings: res.settings }
    jailsLoaded.value = true
  } catch (e: unknown) {
    jailsError.value = fetchApiErrorMessage(e, 'Could not load jails')
    if (!silent) showAlert(jailsError.value, false)
  } finally {
    jailsLoading.value = false
  }
}

async function loadBanned(silent = false) {
  if (!isInstalled.value || bannedLoading.value) return
  bannedLoading.value = true
  bannedError.value = ''
  try {
    const res = await $fetch<Fail2banBannedPayload>('/api/security/fail2ban/banned')
    if (res.ok === false) {
      bannedError.value = res.error || 'Could not load banned IPs'
      if (!silent) showAlert(bannedError.value, false)
      return
    }
    bannedPayload.value = res
    bannedLoaded.value = true
  } catch (e: unknown) {
    bannedError.value = fetchApiErrorMessage(e, 'Could not load banned IPs')
    if (!silent) showAlert(bannedError.value, false)
  } finally {
    bannedLoading.value = false
  }
}

async function refreshAll(silent = false) {
  await loadSummary(silent)
  if (activeTab.value === 'jails' && isInstalled.value) {
    await loadJails(silent)
  }
  if (activeTab.value === 'banned' && isInstalled.value) {
    await loadBanned(silent)
  }
}

watch(activeTab, (tab) => {
  if (!isInstalled.value || loading.value) return
  if (tab === 'jails' && !jailsLoaded.value && !jailsLoading.value) void loadJails(true)
  if (tab === 'banned' && !bannedLoaded.value && !bannedLoading.value) void loadBanned(true)
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
    const res = await $fetch<{ ok?: boolean; error?: string }>('/api/security/fail2ban/start', {
      method: 'POST'
    })
    if (res.ok === false) {
      showAlert(res.error || 'Start failed', false)
      return
    }
    showAlert('Fail2ban service started', true)
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(fetchApiErrorMessage(e), false)
  } finally {
    startBusy.value = false
  }
}

async function onReload() {
  reloadBusy.value = true
  try {
    const res = await $fetch<{ ok?: boolean; error?: string }>('/api/security/fail2ban/reload', {
      method: 'POST'
    })
    if (res.ok === false) {
      showAlert(res.error || 'Reload failed', false)
      return
    }
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
    const res = await $fetch<{ ok?: boolean; error?: string }>('/api/security/fail2ban/unban', {
      method: 'POST',
      body: { ip }
    })
    if (res.ok === false) {
      showAlert(res.error || 'Unban failed', false)
      return
    }
    showAlert(`Unbanned ${ip}`, true)
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Unban failed', false)
  }
}

async function onSyncGeoip() {
  syncGeoBusy.value = true
  try {
    const res = await $fetch<{
      ok?: boolean
      error?: string
      syncedAt?: string
      resolved?: number
      total?: number
    }>('/api/security/geoip/sync', {
      method: 'POST'
    })
    if (res.ok === false) {
      showAlert(res.error || 'Country database sync failed', false)
      return
    }
    const stats =
      typeof res.total === 'number'
        ? ` — ${res.resolved ?? 0}/${res.total} resolved`
        : ''
    showAlert(
      res.syncedAt
        ? `Country database synced (${new Date(res.syncedAt).toLocaleString()})${stats}`
        : `Country database synced${stats}`,
      true
    )
    bannedLoaded.value = false
    await loadBanned(true)
  } catch (e: unknown) {
    showAlert(fetchApiErrorMessage(e), false)
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
    const res = await $fetch<{ ok?: boolean; error?: string; settings: typeof settings; warnings?: string[] }>(
      '/api/security/fail2ban/settings',
      { method: 'PUT', body: settings }
    )
    if (res.ok === false) {
      const message = res.error || 'Settings apply failed'
      showAlert(message, false)
      return { ok: false, message }
    }
    data.value = { ...data.value, settings: res.settings }
    const warn = res.warnings?.length ? ` (${res.warnings.join('; ')})` : ''
    const message = `Settings applied${warn}`
    showAlert(message, true)
    jailsLoaded.value = false
    await refreshAll(true)
    return { ok: true, message }
  } catch (e: unknown) {
    const message = fetchApiErrorMessage(e)
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
    const res = await $fetch<{
      ok?: boolean
      error?: string
      settings?: Fail2banSummary['settings']
    }>(
      '/api/security/fail2ban/settings',
      { method: 'PUT', body: { resetJail: jail } }
    )
    if (res.ok === false) {
      showAlert(res.error || 'Reset failed', false)
      return
    }
    if (res.settings) data.value = { ...data.value, settings: res.settings }
    showAlert(`${jail} reset to defaults`, true)
    jailsLoaded.value = false
    await refreshAll(true)
  } catch (e: unknown) {
    showAlert(fetchApiErrorMessage(e, 'Reset failed'), false)
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

onMounted(async () => {
  await loadSummary()
  resumePollIfRunning()
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

.events-ip {
  min-width: 8rem;
  max-width: 10rem;
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

.warn {
  border-left: 3px solid var(--warning, #ca8a04);
}

.tab-panel {
  min-height: 120px;
}
</style>
