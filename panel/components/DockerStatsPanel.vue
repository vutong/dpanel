<template>
  <section class="card docker-stats" :aria-busy="statsLoading">
    <p
      v-if="collectorPaused"
      class="collector-pause-hint pill pill-warn"
    >
      Background refresh paused while an operation is running.
    </p>
    <p
      v-if="cacheHint"
      class="cache-hint"
      :class="cacheStale ? 'pill pill-warn' : 'muted'"
    >
      {{ cacheHint }}
    </p>
    <p v-if="fetchError && !data" class="alert alert-error">{{ fetchError }}</p>

    <div v-else class="stats-layout">
      <div class="stats-main">
        <!-- Chart -->
        <div class="chart-wrap">
          <div v-if="!chartReady" class="chart-skeleton" aria-hidden="true">
            <span class="skeleton skeleton-block chart-skeleton-block" />
            <div class="chart-axis chart-axis-skel">
              <span class="skeleton skeleton-text" style="width: 1.5rem" />
              <span class="skeleton skeleton-text" style="width: 1.5rem" />
              <span class="skeleton skeleton-text" style="width: 2rem" />
            </div>
          </div>
          <template v-else>
            <svg
              class="chart-svg"
              viewBox="0 0 400 120"
              preserveAspectRatio="none"
              aria-label="CPU and RAM usage over time"
            >
              <line
                v-for="y in gridYs"
                :key="y"
                x1="0"
                :y1="y"
                x2="400"
                :y2="y"
                class="grid-line"
              />
              <polyline v-if="cpuPoints" :points="cpuPoints" class="line cpu" fill="none" />
              <polyline v-if="memPoints" :points="memPoints" class="line mem" fill="none" />
            </svg>
            <div class="chart-axis">
              <span>0%</span>
              <span>50%</span>
              <span>100%</span>
            </div>
          </template>
        </div>

        <!-- Disk breakdown -->
        <h3 class="sub-title">Stack disk breakdown</h3>
        <template v-if="statsLoading">
          <div class="disk-summary skel-disk" aria-hidden="true">
            <div class="disk-head">
              <span class="skeleton skeleton-text" style="width: 5.5rem" />
              <span class="skeleton skeleton-text" style="width: 7rem" />
            </div>
            <span class="skeleton skeleton-bar" />
          </div>
          <div class="skel-table" aria-hidden="true">
            <div v-for="n in 4" :key="n" class="skeleton-row skel-table-row">
              <span class="skeleton skeleton-line" style="width: 42%" />
              <span class="skeleton skeleton-line" style="width: 18%" />
              <span class="skeleton skeleton-line" style="width: 14%" />
            </div>
          </div>
        </template>
        <template v-else>
          <div v-if="disk" class="disk-summary">
            <div class="disk-head">
              <span class="metric-label">Stack volume</span>
              <span class="metric-value">
                {{ formatBytes(disk.stackUsedBytes) }}
                <span class="metric-of">/ {{ formatBytes(disk.stackTotalBytes) }}</span>
                <span class="pct">({{ diskPct.toFixed(1) }}%)</span>
              </span>
            </div>
            <div class="bar disk-bar">
              <div class="bar-fill disk" :style="{ width: `${diskPct}%` }" />
            </div>
          </div>
          <div v-if="diskBreakdownRows.length" class="table-wrap disk-table-wrap">
            <table class="table stats-table compact">
              <thead>
                <tr>
                  <th>Path</th>
                  <th class="num">Size</th>
                  <th class="num">Share</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in diskBreakdownRows" :key="row.path">
                  <td>
                    <code>{{ row.path }}/</code>
                    <span class="row-label">{{ row.label }}</span>
                  </td>
                  <td class="num">{{ formatBytes(row.bytes) }}</td>
                  <td class="num">{{ breakdownShare(row.bytes) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>

        <!-- Containers -->
        <div class="containers-head">
          <h3 class="sub-title">Containers</h3>
          <div v-if="!statsLoading && containers.length" class="containers-head-actions">
            <label v-if="containersExpanded" class="limit-select-wrap">
              <span class="muted">Show</span>
              <select v-model.number="containerLimit" class="limit-select">
                <option v-for="n in containerLimitOptions" :key="n" :value="n">{{ n }}</option>
              </select>
            </label>
            <button
              type="button"
              class="toggle-btn"
              @click="containersExpanded = !containersExpanded"
            >
              {{ containersExpanded ? 'Hide list' : `Show list (${containers.length})` }}
            </button>
          </div>
          <span
            v-else-if="statsLoading"
            class="skeleton skeleton-text"
            style="width: 5.5rem"
            aria-hidden="true"
          />
        </div>
        <div v-if="statsLoading" class="skel-table" aria-hidden="true">
          <div v-for="n in 3" :key="n" class="skeleton-row skel-table-row">
            <span class="skeleton skeleton-line" style="width: 48%" />
            <span class="skeleton skeleton-line" style="width: 16%" />
            <span class="skeleton skeleton-line" style="width: 22%" />
          </div>
        </div>
        <p v-else-if="!containers.length" class="muted empty">No running containers.</p>
        <div v-else-if="containersExpanded" class="table-wrap containers-table-wrap">
          <table class="table stats-table compact">
            <thead>
              <tr>
                <th>
                  <button
                    type="button"
                    class="th-sort"
                    :class="{ active: containerSort === 'name' }"
                    @click="containerSort = 'name'"
                  >
                    Container
                    <span class="sort-icons" aria-hidden="true">
                      <i class="sort-up" />
                      <i class="sort-down" />
                    </span>
                  </button>
                </th>
                <th class="num">
                  <button
                    type="button"
                    class="th-sort th-sort-num"
                    :class="{ active: containerSort === 'cpu' }"
                    @click="containerSort = 'cpu'"
                  >
                    CPU %
                    <span class="sort-icons" aria-hidden="true">
                      <i class="sort-up" />
                      <i class="sort-down" />
                    </span>
                  </button>
                </th>
                <th class="num">
                  <button
                    type="button"
                    class="th-sort th-sort-num"
                    :class="{ active: containerSort === 'mem' }"
                    @click="containerSort = 'mem'"
                  >
                    RAM
                    <span class="sort-icons" aria-hidden="true">
                      <i class="sort-up" />
                      <i class="sort-down" />
                    </span>
                  </button>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="c in visibleContainers" :key="c.name">
                <td><code class="cname">{{ c.name }}</code></td>
                <td class="num">{{ c.cpuPercent.toFixed(2) }}%</td>
                <td class="num">
                  {{ formatBytes(c.memUsedBytes) }}
                  <span v-if="c.memLimitBytes" class="limit-of"
                    >/ {{ formatBytes(c.memLimitBytes) }}</span
                  >
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div class="stats-side">
        <aside class="host-metrics" aria-label="Server metrics">
          <h3 class="metrics-title">Server</h3>

          <template v-if="statsLoading">
            <div v-for="n in 3" :key="n" class="metric-row" aria-hidden="true">
              <span class="skeleton" style="width: 1.25rem; height: 1.25rem; border-radius: 4px" />
              <div class="metric-body">
                <span class="skeleton skeleton-text" style="width: 2.5rem; margin-bottom: 0.35rem" />
                <span class="skeleton skeleton-line" style="width: 70%; margin-bottom: 0.4rem" />
                <span class="skeleton skeleton-bar" />
              </div>
            </div>
          </template>
          <template v-else>
            <div class="metric-row">
              <span class="metric-icon" aria-hidden="true">🧠</span>
              <div class="metric-body">
                <span class="metric-name">RAM</span>
                <span class="metric-detail">
                  {{ formatBytes(host?.memUsedBytes) }}
                  <span class="metric-pct">({{ memPct.toFixed(0) }}%)</span>
                  <span class="metric-of">/ {{ formatBytes(host?.memTotalBytes) }}</span>
                </span>
                <div class="bar metric-bar">
                  <div class="bar-fill mem" :style="{ width: `${memPct}%` }" />
                </div>
              </div>
            </div>

            <div class="metric-row">
              <span class="metric-icon" aria-hidden="true">💾</span>
              <div class="metric-body">
                <span class="metric-name">Disk</span>
                <div class="metric-detail-row">
                  <span class="metric-detail">
                    {{ formatBytes(host?.diskUsedBytes) }}
                    <span v-if="host?.diskKind" class="disk-kind">{{ host.diskKind }}</span>
                    <span class="metric-pct">({{ systemDiskPct.toFixed(0) }}%)</span>
                    <span class="metric-of">/ {{ formatBytes(host?.diskTotalBytes) }}</span>
                  </span>
                  <button
                    type="button"
                    class="disk-check-btn"
                    :disabled="diskTesting"
                    @click="runDiskTest"
                  >
                    {{ diskTesting ? 'Checking…' : 'Check' }}
                  </button>
                </div>
                <div class="bar metric-bar">
                  <div class="bar-fill disk-sys" :style="{ width: `${systemDiskPct}%` }" />
                </div>
                <p v-if="diskTestError" class="disk-test-error">{{ diskTestError }}</p>
              </div>
            </div>

            <div class="metric-row metric-row-cpu">
              <span class="metric-icon" aria-hidden="true">⚡</span>
              <div class="metric-body">
                <span class="metric-name">CPU · avg {{ currentCpu.toFixed(1) }}%</span>
                <ul v-if="cpuCores.length" class="cpu-list">
                  <li v-for="core in cpuCores" :key="core.index">
                    <span class="cpu-label">CPU {{ core.index + 1 }}</span>
                    <div class="cpu-track">
                      <div class="cpu-fill" :style="{ width: `${core.percent}%` }" />
                    </div>
                    <span class="cpu-pct">{{ core.percent.toFixed(0) }}%</span>
                  </li>
                </ul>
                <div v-else class="cpu-skel" aria-hidden="true">
                  <div v-for="n in 4" :key="n" class="skeleton-row" style="margin-bottom: 0.4rem">
                    <span class="skeleton skeleton-line-sm" style="width: 3rem" />
                    <span class="skeleton skeleton-bar" style="flex: 1" />
                    <span class="skeleton skeleton-line-sm" style="width: 2rem" />
                  </div>
                </div>
              </div>
            </div>

            <div v-if="loadHint" class="load-hint muted">{{ loadHint }}</div>
          </template>
        </aside>

        <SecurityDashboardPanel />
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
import { formatBytes } from '~/composables/useFormatBytes'

type CpuCore = { index: number; percent: number }

type DiskStorage = {
  kind: 'hdd' | 'ssd' | 'nvme' | 'unknown'
  device: string
  readMbps: number | null
  writeMbps: number | null
  rotational: number | null
  probedAt?: string
}

type StatsPayload = {
  ok?: boolean
  host: {
    cpuPercent: number
    memUsedBytes: number
    memTotalBytes: number
    cpuCores?: CpuCore[]
    diskUsedBytes?: number
    diskTotalBytes?: number
    diskKind?: string
  }
  disk?: {
    stackUsedBytes: number
    stackTotalBytes: number
    breakdown: { label: string; path: string; bytes: number }[]
    storage?: DiskStorage
  }
  containers: {
    name: string
    cpuPercent: number
    memUsedBytes: number
    memLimitBytes: number | null
  }[]
  _cache?: {
    ageSec: number
    stale: boolean
    warming: boolean
  }
  collectorPaused?: boolean
}

type HistoryPoint = { cpu: number; mem: number }

const POLL_MS = 8000
const MAX_POINTS = 45
const HISTORY_STORAGE_KEY = 'dpanel-dashboard-stats-history'

function loadHistoryFromStorage(): HistoryPoint[] {
  if (!import.meta.client) return []
  try {
    const raw = sessionStorage.getItem(HISTORY_STORAGE_KEY)
    const parsed = JSON.parse(raw || '[]') as unknown
    if (!Array.isArray(parsed)) return []
    return parsed
      .filter((p): p is HistoryPoint => typeof p?.cpu === 'number' && typeof p?.mem === 'number')
      .slice(-MAX_POINTS)
  } catch {
    return []
  }
}

function persistHistory(points: HistoryPoint[]) {
  if (!import.meta.client) return
  try {
    sessionStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(points.slice(-MAX_POINTS)))
  } catch {
    /* quota / private mode */
  }
}

const data = ref<StatsPayload | null>(null)
const fetchError = ref('')
const history = ref<HistoryPoint[]>([])
const containersExpanded = ref(false)
const diskTesting = ref(false)
const diskTestError = ref('')
const containerLimitOptions = [25, 50, 100, 200, 350] as const
const containerLimit = ref<(typeof containerLimitOptions)[number]>(25)
const containerSort = ref<'name' | 'cpu' | 'mem'>('mem')

/** First payload not yet loaded — show per-section skeletons. */
const statsLoading = computed(() => !data.value && !fetchError.value)
/** Chart needs ≥2 samples before drawing. */
const chartReady = computed(() => history.value.length >= 2)

const cacheHint = computed(() =>
  formatCacheHint(data.value?._cache, {
    warmingLabel: 'Warming stats cache…',
    hasData: Boolean(data.value?.host?.memTotalBytes)
  })
)
const cacheStale = computed(
  () => Boolean(data.value?._cache?.stale || data.value?._cache?.warming)
)
const collectorPaused = computed(() => Boolean(data.value?.collectorPaused))

const gridYs = [0, 30, 60, 90, 120]

function applyStatsPayload(payload: StatsPayload) {
  if (payload._cache?.warming && !payload.host?.memTotalBytes && data.value) {
    return
  }
  data.value = payload
  fetchError.value = ''
  if (payload.host?.memTotalBytes) {
    const mem = memPctFromHost(payload.host)
    const next = [...history.value, { cpu: payload.host.cpuPercent, mem }]
    history.value = next.length > MAX_POINTS ? next.slice(-MAX_POINTS) : next
  }
}

useLeaderPoll({
  channel: 'dpanel-dashboard-stats',
  intervalMs: POLL_MS,
  followerFallbackMs: 60_000,
  fetcher: async () => {
    try {
      return await $fetch<StatsPayload>('/api/docker/stats')
    } catch (e: unknown) {
      const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
      const msg = err.data?.statusMessage || err.statusMessage || 'Could not load stats'
      if (!data.value) fetchError.value = msg
      throw e
    }
  },
  onData: (payload) => applyStatsPayload(payload)
})

const host = computed(() => data.value?.host)
const currentCpu = computed(() => history.value.at(-1)?.cpu ?? data.value?.host.cpuPercent ?? 0)

const disk = computed(() => data.value?.disk)
const containers = computed(() => data.value?.containers ?? [])
const cpuCores = computed(() => host.value?.cpuCores ?? [])

const diskBreakdownRows = computed(() => {
  const rows = [...(disk.value?.breakdown ?? [])]
  if (!rows.length) return []
  return rows.sort((a, b) => b.bytes - a.bytes).slice(0, 5)
})

const visibleContainers = computed(() => {
  const key = containerSort.value
  const sorted = [...containers.value].sort((a, b) => {
    if (key === 'cpu') return b.cpuPercent - a.cpuPercent
    if (key === 'name') return b.name.localeCompare(a.name)
    return b.memUsedBytes - a.memUsedBytes
  })
  return sorted.slice(0, containerLimit.value)
})

const memPct = computed(() => memPctFromHost(host.value))

const diskPct = computed(() => {
  const d = disk.value
  if (!d?.stackTotalBytes) return 0
  return Math.min(100, (d.stackUsedBytes / d.stackTotalBytes) * 100)
})

const systemDiskPct = computed(() => {
  const h = host.value
  if (!h?.diskTotalBytes) return 0
  return Math.min(100, ((h.diskUsedBytes || 0) / h.diskTotalBytes) * 100)
})

const loadHint = computed(() => {
  const n = cpuCores.value.length
  if (n > 0) return `${n} logical core(s)`
  return null
})

function diskKindLabel(kind: string) {
  const map = { hdd: 'HDD', ssd: 'SSD', nvme: 'NVMe' } as const
  return map[kind as keyof typeof map] || kind.toUpperCase()
}

function applyStorageFromProbe(storage: DiskStorage) {
  if (!data.value?.disk) return
  data.value = {
    ...data.value,
    disk: { ...data.value.disk, storage },
    host: {
      ...data.value.host,
      diskKind: storage.kind !== 'unknown' ? diskKindLabel(storage.kind) : data.value.host.diskKind,
    },
  }
}

async function runDiskTest() {
  diskTestError.value = ''
  diskTesting.value = true
  try {
    const result = await $fetch<{
      ok: boolean
      kind?: string
      device?: string
      readMbps?: number | null
      writeMbps?: number | null
      rotational?: number | null
      probedAt?: string
      error?: string
    }>('/api/docker/disk/test', { method: 'POST' })
    if (!result.ok) {
      diskTestError.value = result.error || 'Disk test failed'
      return
    }
    applyStorageFromProbe({
      kind: (result.kind || 'unknown') as DiskStorage['kind'],
      device: result.device || '',
      readMbps: result.readMbps ?? null,
      writeMbps: result.writeMbps ?? null,
      rotational: result.rotational ?? null,
      probedAt: result.probedAt,
    })
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    diskTestError.value = err.data?.statusMessage || err.statusMessage || 'Disk test failed'
  } finally {
    diskTesting.value = false
  }
}

function memPctFromHost(h?: StatsPayload['host']) {
  if (!h?.memTotalBytes) return 0
  return Math.min(100, (h.memUsedBytes / h.memTotalBytes) * 100)
}

function breakdownShare(bytes: number) {
  const total = disk.value?.stackUsedBytes || 0
  if (!total) return '—'
  return `${((bytes / total) * 100).toFixed(1)}%`
}

function chartPoints(key: 'cpu' | 'mem'): string {
  const pts = history.value
  if (pts.length < 2) return ''
  const w = 400
  const h = 120
  const n = pts.length - 1
  return pts
    .map((p, i) => {
      const x = (i / n) * w
      const y = h - (Math.min(100, Math.max(0, p[key])) / 100) * h
      return `${x},${y}`
    })
    .join(' ')
}

const cpuPoints = computed(() => chartPoints('cpu'))
const memPoints = computed(() => chartPoints('mem'))

onMounted(() => {
  history.value = loadHistoryFromStorage()
})

watch(history, (pts) => persistHistory(pts), { deep: true })
</script>

<style scoped>
.docker-stats {
  margin-top: 0;
}

.cache-hint {
  font-size: var(--text-xs);
  margin: 0 0 0.65rem;
}

.collector-pause-hint {
  font-size: var(--text-xs);
  margin: 0 0 0.65rem;
}

.stats-layout {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1.25rem;
}

@media (min-width: 960px) {
  .stats-layout {
    grid-template-columns: minmax(0, 2fr) minmax(240px, 1fr);
    align-items: start;
  }
}

.stats-main {
  min-width: 0;
}

.stats-side {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  min-width: 0;
}

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

.metric-row {
  display: flex;
  gap: 0.65rem;
  margin-bottom: 1rem;
}

.metric-row-cpu {
  margin-bottom: 0.5rem;
}

.metric-icon {
  font-size: 1.1rem;
  line-height: 1;
  flex-shrink: 0;
  width: 1.35rem;
  text-align: center;
  margin-top: 0.1rem;
}

.metric-body {
  flex: 1;
  min-width: 0;
}

.metric-name {
  display: block;
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--text);
  margin-bottom: 0.2rem;
}

.metric-detail {
  display: block;
  font-size: 0.8125rem;
  color: var(--text);
  line-height: 1.35;
}

.metric-detail-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.45rem;
  margin-bottom: 0.35rem;
}

.metric-detail-row .metric-detail {
  margin-bottom: 0;
  flex: 1;
  min-width: 0;
}

.disk-check-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  border: 1px solid var(--border);
  background: var(--surface-elevated);
  color: var(--muted);
  font-size: 0.72rem;
  font-weight: 500;
  padding: 0 0.55rem;
  min-height: 1.75rem;
  line-height: 1;
  border-radius: 6px;
  cursor: pointer;
}

.disk-check-btn:hover:not(:disabled) {
  color: var(--accent);
  border-color: var(--accent);
}

.disk-check-btn:disabled {
  opacity: 0.65;
  cursor: wait;
}

.disk-test-error {
  margin: 0.35rem 0 0;
  font-size: 0.75rem;
  color: var(--danger, #ef4444);
}

.metric-pct {
  color: var(--muted);
  font-weight: 500;
}

.metric-of {
  color: var(--muted);
}

.disk-kind {
  display: inline-block;
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.1rem 0.35rem;
  margin: 0 0.15rem;
  border-radius: 4px;
  background: var(--accent-muted);
  color: var(--accent);
  vertical-align: middle;
}

.metric-body > .metric-detail {
  margin-bottom: 0.35rem;
}

.metric-bar {
  height: 5px;
  border-radius: 3px;
  background: var(--border);
  overflow: hidden;
}

.bar-fill.mem {
  height: 100%;
  background: var(--success);
  border-radius: 3px;
  transition: width 0.35s ease;
}

.bar-fill.disk-sys {
  height: 100%;
  background: #a78bfa;
  border-radius: 3px;
  transition: width 0.35s ease;
}

.cpu-list {
  list-style: none;
  margin: 0.35rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}

.cpu-list li {
  display: grid;
  grid-template-columns: 3.25rem 1fr 2.25rem;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.75rem;
}

.cpu-label {
  color: var(--muted);
  font-weight: 500;
}

.cpu-track {
  height: 4px;
  border-radius: 2px;
  background: var(--border);
  overflow: hidden;
}

.cpu-fill {
  height: 100%;
  background: var(--accent);
  border-radius: 2px;
  transition: width 0.35s ease;
  min-width: 0;
}

.cpu-pct {
  text-align: right;
  font-variant-numeric: tabular-nums;
  color: var(--text);
}

.load-hint {
  font-size: 0.72rem;
  margin-top: 0.5rem;
  padding-top: 0.5rem;
  border-top: 1px solid var(--border);
}

.chart-wrap {
  margin-bottom: 1.25rem;
  position: relative;
}

.chart-skeleton {
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
}

.chart-skeleton-block {
  height: 7.5rem;
  border-radius: 8px;
}

.chart-axis-skel {
  display: flex;
  justify-content: space-between;
}

.skel-disk {
  margin-bottom: 0.75rem;
}

.skel-table {
  margin: 0.35rem 0 1rem;
}

.skel-table-row {
  margin-bottom: 0.55rem;
}

.cpu-skel {
  margin-top: 0.35rem;
}

.chart-svg {
  width: 100%;
  height: 140px;
  display: block;
  background: var(--bg-subtle);
  border-radius: 8px;
  border: 1px solid var(--border);
}

.grid-line {
  stroke: var(--border);
  stroke-width: 0.5;
  vector-effect: non-scaling-stroke;
}

.line {
  stroke-width: 2;
  vector-effect: non-scaling-stroke;
  stroke-linejoin: round;
  stroke-linecap: round;
}

.line.cpu {
  stroke: var(--accent);
}

.line.mem {
  stroke: var(--success);
}

.chart-axis {
  display: flex;
  justify-content: space-between;
  font-size: 0.68rem;
  color: var(--muted);
  margin-top: 0.25rem;
  padding: 0 0.15rem;
}

.sub-title {
  font-size: 0.88rem;
  font-weight: 600;
  margin: 0 0 0.65rem;
  color: var(--text);
}

.containers-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 0.65rem;
}

.containers-head .sub-title {
  margin-bottom: 0;
}

.containers-head-actions {
  display: inline-flex;
  align-items: center;
  gap: 0.65rem;
}

.limit-select-wrap {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.78rem;
}

.limit-select {
  min-height: var(--control-h-sm, 1.75rem);
  padding: 0 0.45rem;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--surface-elevated);
  color: var(--text);
  font-size: 0.78rem;
}

.toggle-btn {
  border: 1px solid var(--border);
  background: var(--surface-elevated);
  color: var(--muted);
  font-size: 0.8rem;
  padding: 0.3rem 0.6rem;
  border-radius: 7px;
  cursor: pointer;
}

.toggle-btn:hover {
  color: var(--accent);
  border-color: var(--accent);
}

.containers-table-wrap {
  max-height: 500px;
  overflow: auto;
  margin-bottom: 0.25rem;
}

.th-sort {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  border: 0;
  background: transparent;
  color: inherit;
  font: inherit;
  font-weight: 600;
  padding: 0;
  cursor: pointer;
}

.th-sort-num {
  justify-content: flex-end;
  width: 100%;
}

.th-sort:hover {
  color: var(--accent);
}

.th-sort.active {
  color: var(--text);
}

.sort-icons {
  display: inline-flex;
  flex-direction: column;
  gap: 1px;
  width: 0.55rem;
}

.sort-up,
.sort-down {
  display: block;
  width: 0;
  height: 0;
  border-left: 0.22rem solid transparent;
  border-right: 0.22rem solid transparent;
  opacity: 0.35;
}

.sort-up {
  border-bottom: 0.28rem solid currentColor;
}

.sort-down {
  border-top: 0.28rem solid currentColor;
}

.th-sort.active .sort-down {
  opacity: 1;
  color: var(--accent);
}

.disk-summary {
  margin-bottom: 0.75rem;
}

.disk-head {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  align-items: baseline;
  gap: 0.5rem;
  margin-bottom: 0.4rem;
}

.metric-label {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--muted);
}

.metric-value {
  font-size: 0.9rem;
  font-weight: 600;
}

.metric-of {
  font-weight: 500;
  color: var(--muted);
}

.pct {
  font-size: 0.82rem;
  color: var(--muted);
  margin-left: 0.25rem;
}

.bar {
  height: 6px;
  border-radius: 3px;
  background: var(--border);
  overflow: hidden;
}

.bar-fill.disk {
  height: 100%;
  background: #a78bfa;
  border-radius: 3px;
  transition: width 0.35s ease;
}

.disk-table-wrap {
  margin-bottom: 1rem;
}

.stats-table.compact th,
.stats-table.compact td {
  padding: 0.4rem 0.5rem;
  font-size: 0.8125rem;
}

.row-label {
  display: block;
  font-size: 0.72rem;
  color: var(--muted);
  margin-top: 0.1rem;
}

.stats-table .num {
  text-align: right;
  white-space: nowrap;
}

.cname {
  font-size: 0.78rem;
  word-break: break-all;
}

.limit-of {
  color: var(--muted);
  font-size: 0.82rem;
}

.empty {
  font-size: 0.9rem;
  margin: 0.5rem 0;
}

.muted {
  color: var(--muted);
}
</style>
