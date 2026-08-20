<template>
  <div class="results">
    <PageLoader v-if="loading" label="Loading results…" />

    <div v-else-if="!scan" class="card muted empty-card">
      Select a scan from the <strong>Results</strong> history, or run a new scan.
    </div>

    <template v-else>
      <div class="card summary">
        <dl class="meta">
          <div>
            <dt>Target</dt>
            <dd><code>{{ scan.scanPath }}</code></dd>
          </div>
          <div>
            <dt>Status</dt>
            <dd>{{ statusLabel(scan.status) }}</dd>
          </div>
          <div>
            <dt>Started</dt>
            <dd>{{ formatTime(scan.startedAt) }}</dd>
          </div>
          <div v-if="scan.finishedAt">
            <dt>Finished</dt>
            <dd>{{ formatTime(scan.finishedAt) }}</dd>
          </div>
          <div>
            <dt>Infected</dt>
            <dd>
              <strong>{{ scan.status === 'running' ? '—' : scan.infectedCount ?? 0 }}</strong>
            </dd>
          </div>
        </dl>

        <p v-if="scan.status === 'error'" class="alert alert-error">{{ scan.error || 'Scan failed' }}</p>
        <p v-else-if="scan.status === 'running'" class="muted">Scan still running…</p>
      </div>

      <div v-if="scan.infected?.length" class="card hits-card">
        <div class="section-head">
          <h3 class="section-title">Infected files</h3>
          <NuxtLink to="/settings/clamav" class="link-sm">ClamAV settings</NuxtLink>
        </div>
        <ul class="hits">
          <li v-for="(h, i) in scan.infected" :key="i">
            <span v-if="h.domain" class="domain">{{ h.domain }}</span>
            <code>{{ h.relPath || h.path }}</code>
          </li>
        </ul>
      </div>

      <div v-else-if="scan.status === 'ok'" class="card muted empty-card">
        No infections detected in this scan.
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import type { ClamavScanDetail } from '~/composables/useClamavScan'

const props = defineProps<{
  scanId?: string | null
}>()

const scan = ref<ClamavScanDetail | null>(null)
const loading = ref(false)

async function load(id?: string | null) {
  const target = id ?? props.scanId
  if (!target) {
    scan.value = null
    return
  }
  loading.value = true
  try {
    const res = await $fetch<{ scan?: ClamavScanDetail | null }>(
      `/api/security/clamav/scans?id=${encodeURIComponent(target)}`
    )
    scan.value = res.scan ?? null
  } catch {
    scan.value = null
  } finally {
    loading.value = false
  }
}

function formatTime(iso: string) {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

function statusLabel(st: string) {
  if (st === 'running') return 'Running'
  if (st === 'error') return 'Error'
  return 'Complete'
}

watch(
  () => props.scanId,
  (id) => load(id),
  { immediate: true }
)

defineExpose({ load, scan })
</script>

<style scoped>
.empty-card {
  padding: 1rem;
  font-size: 0.875rem;
}

.summary {
  margin-bottom: 1rem;
}

.meta {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 0.75rem 1.5rem;
  margin: 0;
}

.meta dt {
  font-size: 0.75rem;
  color: var(--muted);
}

.meta dd {
  margin: 0;
  font-weight: 600;
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

.hits {
  margin: 0;
  padding-left: 1.25rem;
}

.hits li {
  margin: 0.35rem 0;
  font-size: 0.8125rem;
}

.domain {
  font-weight: 600;
  margin-right: 0.5rem;
}

.muted {
  color: var(--muted);
}
</style>
