<template>
  <section class="card docker-stats">
    <div class="stats-head">
      <h2>Docker stats</h2>
      <button type="button" class="btn btn-ghost btn-sm" :disabled="pending" @click="refresh()">
        Refresh
      </button>
    </div>

    <PageLoader v-if="pending && !data" label="Loading stats…" />
    <p v-else-if="error" class="alert alert-error">{{ error }}</p>
    <template v-else-if="data">
      <div class="host-metrics">
        <div class="metric">
          <span class="metric-label">Host CPU</span>
          <span class="metric-value">{{ data.host.cpuPercent.toFixed(1) }}%</span>
          <div class="bar"><div class="bar-fill cpu" :style="{ width: barWidth(data.host.cpuPercent) }" /></div>
        </div>
        <div class="metric">
          <span class="metric-label">Host RAM</span>
          <span class="metric-value">
            {{ formatBytes(data.host.memUsedBytes) }}
            <span class="metric-of">/ {{ formatBytes(data.host.memTotalBytes) }}</span>
          </span>
          <div class="bar">
            <div class="bar-fill mem" :style="{ width: memBarWidth }" />
          </div>
        </div>
      </div>

      <p v-if="!data.containers.length" class="muted empty">No running containers reported.</p>
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
            <tr v-for="c in data.containers" :key="c.name">
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
      <p class="hint">Sorted by CPU % (lowest first). Shared services (MariaDB, Redis, …) appear here too.</p>
    </template>
  </section>
</template>

<script setup lang="ts">
import { formatBytes } from '~/composables/useFormatBytes'

type StatsPayload = {
  host: { cpuPercent: number; memUsedBytes: number; memTotalBytes: number }
  containers: {
    name: string
    cpuPercent: number
    memUsedBytes: number
    memLimitBytes: number | null
  }[]
}

const { data, pending, error, refresh } = useFetch<StatsPayload>('/api/docker/stats', {
  server: false,
  immediate: true
})

const memBarWidth = computed(() => {
  const h = data.value?.host
  if (!h?.memTotalBytes) return '0%'
  const pct = Math.min(100, (h.memUsedBytes / h.memTotalBytes) * 100)
  return `${pct}%`
})

function barWidth(pct: number) {
  return `${Math.min(100, Math.max(0, pct))}%`
}
</script>

<style scoped>
.docker-stats {
  margin-top: 1.5rem;
}
.stats-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  margin-bottom: 1rem;
}
.stats-head h2 {
  font-size: 1.05rem;
}
.btn-sm {
  font-size: 0.82rem;
  padding: 0.35rem 0.65rem;
}
.host-metrics {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 1rem;
  margin-bottom: 1.25rem;
}
.metric-label {
  display: block;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--muted);
  margin-bottom: 0.25rem;
}
.metric-value {
  font-size: 1.1rem;
  font-weight: 600;
}
.metric-of {
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--muted);
}
.bar {
  height: 6px;
  border-radius: 3px;
  background: var(--border);
  margin-top: 0.5rem;
  overflow: hidden;
}
.bar-fill {
  height: 100%;
  border-radius: 3px;
  transition: width 0.3s ease;
}
.bar-fill.cpu {
  background: var(--accent);
}
.bar-fill.mem {
  background: var(--success);
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
.hint {
  font-size: 0.78rem;
  color: var(--muted);
  margin-top: 0.75rem;
}
</style>
