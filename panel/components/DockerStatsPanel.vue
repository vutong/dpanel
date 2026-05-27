<template>
  <section class="card docker-stats">
    <div class="stats-head">
      <h2>Host resources</h2>
      <span v-if="live" class="live-badge">Live</span>
    </div>

    <p v-if="fetchError && !data" class="alert alert-error">{{ fetchError }}</p>

    <template v-else>
      <div class="chart-wrap">
        <div class="chart-legend">
          <span class="legend-item"><i class="dot cpu" /> CPU {{ currentCpu.toFixed(1) }}%</span>
          <span class="legend-item"><i class="dot mem" /> RAM {{ currentMemPct.toFixed(1) }}%</span>
        </div>
        <p v-if="history.length < 2" class="chart-wait muted">Collecting samples…</p>
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
      </div>

      <h3 class="sub-title">Disk usage</h3>
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
      <div v-if="disk?.breakdown?.length" class="table-wrap disk-table-wrap">
        <table class="table stats-table">
          <thead>
            <tr>
              <th>Path</th>
              <th class="num">Size</th>
              <th class="num">Share</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in disk.breakdown" :key="row.path">
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

      <h3 class="sub-title">Containers</h3>
      <p v-if="!containers.length" class="muted empty">No running containers.</p>
      <div v-else class="table-wrap">
        <table class="table stats-table">
          <thead>
            <tr>
              <th>Container</th>
              <th class="num">CPU %</th>
              <th class="num">RAM</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in containers" :key="c.name">
              <td><code class="cname">{{ c.name }}</code></td>
              <td class="num">{{ c.cpuPercent.toFixed(2) }}%</td>
              <td class="num">
                {{ formatBytes(c.memUsedBytes) }}
                <span v-if="c.memLimitBytes" class="limit-of">/ {{ formatBytes(c.memLimitBytes) }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </section>
</template>

<script setup lang="ts">
import { formatBytes } from '~/composables/useFormatBytes'

type StatsPayload = {
  host: { cpuPercent: number; memUsedBytes: number; memTotalBytes: number }
  disk?: {
    stackUsedBytes: number
    stackTotalBytes: number
    breakdown: { label: string; path: string; bytes: number }[]
  }
  containers: {
    name: string
    cpuPercent: number
    memUsedBytes: number
    memLimitBytes: number | null
  }[]
}

type HistoryPoint = { cpu: number; mem: number }

const POLL_MS = 4000
const MAX_POINTS = 45

const data = ref<StatsPayload | null>(null)
const fetchError = ref('')
const live = ref(false)
const history = ref<HistoryPoint[]>([])

const gridYs = [0, 30, 60, 90, 120]

let timer: ReturnType<typeof setInterval> | null = null

const currentCpu = computed(() => history.value.at(-1)?.cpu ?? data.value?.host.cpuPercent ?? 0)
const currentMemPct = computed(() => history.value.at(-1)?.mem ?? memPctFromHost(data.value?.host))

const disk = computed(() => data.value?.disk)
const containers = computed(() => data.value?.containers ?? [])

const diskPct = computed(() => {
  const d = disk.value
  if (!d?.stackTotalBytes) return 0
  return Math.min(100, (d.stackUsedBytes / d.stackTotalBytes) * 100)
})

function memPctFromHost(host?: StatsPayload['host']) {
  if (!host?.memTotalBytes) return 0
  return Math.min(100, (host.memUsedBytes / host.memTotalBytes) * 100)
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

async function poll() {
  try {
    const payload = await $fetch<StatsPayload>('/api/docker/stats')
    data.value = payload
    fetchError.value = ''
    live.value = true
    const mem = memPctFromHost(payload.host)
    const next = [...history.value, { cpu: payload.host.cpuPercent, mem }]
    history.value = next.length > MAX_POINTS ? next.slice(-MAX_POINTS) : next
  } catch (e: unknown) {
    live.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    const msg = err.data?.statusMessage || err.statusMessage || 'Could not load stats'
    if (!data.value) fetchError.value = msg
  }
}

onMounted(() => {
  void poll()
  timer = setInterval(() => void poll(), POLL_MS)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<style scoped>
.docker-stats {
  margin-top: 0;
}
.stats-head {
  display: flex;
  align-items: center;
  gap: 0.65rem;
  margin-bottom: 1rem;
}
.stats-head h2 {
  font-size: 1.05rem;
}
.live-badge {
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  padding: 0.2rem 0.45rem;
  border-radius: 4px;
  background: var(--success-muted);
  color: var(--success);
  font-weight: 600;
}
.chart-wrap {
  margin-bottom: 1.5rem;
  position: relative;
}
.chart-wait {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.85rem;
  pointer-events: none;
  z-index: 1;
}
.chart-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  margin-bottom: 0.5rem;
  font-size: 0.85rem;
  font-weight: 500;
}
.legend-item {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}
.dot {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
}
.dot.cpu {
  background: var(--accent);
}
.dot.mem {
  background: var(--success);
}
.chart-svg {
  width: 100%;
  height: 160px;
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
  font-size: 0.95rem;
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
  margin-bottom: 1.25rem;
}
.row-label {
  display: block;
  font-size: 0.75rem;
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
</style>
