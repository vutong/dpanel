<template>
  <div class="history">
    <div class="toolbar">
      <label class="field-inline">
        <span class="label-sm">Filter</span>
        <select v-model="filterDomain" class="select select-sm" @change="load">
          <option value="">All scans</option>
          <option v-for="s in sites" :key="s.domain" :value="s.domain">{{ s.domain }}</option>
        </select>
      </label>
      <button type="button" class="btn btn-ghost btn-sm toolbar-refresh" :disabled="loading" @click="load">
        <AppIcon name="refresh" :size="14" />
        {{ loading ? 'Refreshing…' : 'Refresh' }}
      </button>
    </div>

    <PageLoader v-if="loading && !scans.length" label="Loading scan history…" />

    <div v-else-if="!scans.length" class="card muted empty-card">
      No scans recorded yet. Run a scan from the <strong>Scan</strong> tab or a website page.
    </div>

    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>When</th>
            <th>Target</th>
            <th>Status</th>
            <th>Infected</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="s in scans"
            :key="s.id"
            :class="{ selected: selectedId === s.id, running: s.status === 'running' }"
          >
            <td class="time">{{ formatTime(s.finishedAt || s.startedAt) }}</td>
            <td>
              <code>{{ s.target === 'all' ? 'all apps' : s.target }}</code>
            </td>
            <td>
              <span class="status" :class="`status-${s.status}`">{{ statusLabel(s.status) }}</span>
            </td>
            <td>{{ s.status === 'running' ? '—' : s.infectedCount ?? 0 }}</td>
            <td>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                :disabled="s.status === 'running'"
                @click="emit('select', s.id)"
              >
                View
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { ClamavScanSummary } from '~/composables/useClamavScan'

const props = defineProps<{
  sites: { domain: string }[]
  selectedId?: string | null
}>()

const emit = defineEmits<{ select: [id: string] }>()

const scans = ref<ClamavScanSummary[]>([])
const filterDomain = ref('')
const loading = ref(false)

async function load() {
  loading.value = true
  try {
    const q = new URLSearchParams({ limit: '30' })
    if (filterDomain.value) q.set('domain', filterDomain.value)
    const res = await $fetch<{ scans?: ClamavScanSummary[] }>(
      `/api/security/clamav/scans?${q}`
    )
    scans.value = res.scans ?? []
  } catch {
    scans.value = []
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
  () => props.selectedId,
  () => {
    /* keep selection highlight */
  }
)

defineExpose({ load, refresh: load })

onMounted(() => load())
</script>

<style scoped>
.history {
  margin-bottom: 1rem;
}

.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
  margin-bottom: 0.75rem;
}

.field-inline {
  display: flex;
  align-items: center;
  gap: 0.375rem;
}

.label-sm {
  font-size: var(--text-sm);
  color: var(--muted);
  white-space: nowrap;
}

.select-sm {
  min-width: 10rem;
}

.toolbar-refresh {
  margin-left: auto;
}

.table-wrap {
  padding: 0;
  overflow-x: auto;
}

.table {
  width: 100%;
  font-size: 0.8125rem;
}

.time {
  white-space: nowrap;
  color: var(--muted);
}

.status-running {
  color: var(--accent);
}

.status-ok {
  color: var(--success, #16a34a);
}

.status-error {
  color: var(--danger, #dc2626);
}

tr.selected {
  background: var(--surface-2);
}

tr.running {
  font-style: italic;
}

.empty-card {
  padding: 1rem;
  font-size: 0.875rem;
}

.muted {
  color: var(--muted);
}
</style>
