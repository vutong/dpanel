<template>
  <div v-if="open" class="stream-backdrop" @click.self="emit('close')">
    <div class="stream-modal card" role="dialog" aria-labelledby="clam-scan-title">
      <header class="stream-header">
        <div>
          <h2 id="clam-scan-title">Scan Virus</h2>
          <p class="stream-sub">{{ domain }}</p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" @click="emit('close')">Close</button>
      </header>

      <PageLoader v-if="precheckPending" label="Checking ClamAV…" />

      <template v-else>
        <div v-if="!clamInstalled" class="alert alert-warn">
          ClamAV is not installed on this VPS.
          <NuxtLink to="/settings/clamav" class="link-inline">Install from Settings → ClamAV</NuxtLink>
        </div>

        <div v-else-if="globalScanRunning && !domainScanRunning" class="alert alert-warn">
          Another scan is running
          (<code>{{ activeScan?.target === 'all' ? 'all apps' : activeScan?.target }}</code>).
          Wait for it to finish.
        </div>

        <dl v-if="lastScan" class="last-scan">
          <div>
            <dt>Last scan</dt>
            <dd>{{ formatTime(lastScan.finishedAt || lastScan.startedAt) }}</dd>
          </div>
          <div>
            <dt>Result</dt>
            <dd>
              <span v-if="lastScan.status === 'running'" class="badge-running">Running</span>
              <span v-else-if="lastScan.status === 'error'" class="badge-error">Error</span>
              <span v-else-if="(lastScan.infectedCount ?? 0) > 0" class="badge-warn">
                {{ lastScan.infectedCount }} infected
              </span>
              <span v-else class="badge-ok">Clean</span>
            </dd>
          </div>
        </dl>
        <p v-else class="muted">No scan recorded for this site yet.</p>

        <p v-if="polling" class="scan-progress muted">
          Scan started — running in background. You can close this dialog; check back shortly.
        </p>
        <p v-if="startError" class="alert alert-error">{{ startError }}</p>
      </template>

      <footer class="stream-footer">
        <NuxtLink to="/settings/clamav?tab=results" class="btn btn-ghost btn-sm">All results</NuxtLink>
        <button type="button" class="btn btn-ghost btn-sm" @click="emit('close')">Cancel</button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="!canScan || starting"
          @click="onStart"
        >
          {{ starting ? 'Starting…' : domainScanRunning || polling ? 'Scan running…' : 'Start scan' }}
        </button>
      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { ClamavScanSummary } from '~/composables/useClamavScan'

const props = defineProps<{
  open: boolean
  domain: string
}>()

const emit = defineEmits<{ close: []; started: [scanId: string] }>()

const clamInstalled = ref(false)
const precheckPending = ref(false)
const lastScan = ref<ClamavScanSummary | null>(null)
const activeScan = ref<ClamavScanSummary | null>(null)
const globalScanRunning = ref(false)
const domainScanRunning = ref(false)
const starting = ref(false)
const polling = ref(false)

const canScan = computed(
  () =>
    clamInstalled.value &&
    !globalScanRunning.value &&
    !domainScanRunning.value &&
    !polling.value &&
    !starting.value
)

async function precheck() {
  if (!props.domain) return
  precheckPending.value = true
  try {
    const [clam, site] = await Promise.all([
      $fetch<{ installed?: boolean }>('/api/security/clamav'),
      $fetch<{
        lastScan?: ClamavScanSummary | null
        activeScan?: ClamavScanSummary | null
        globalScanRunning?: boolean
      }>(`/api/websites/${encodeURIComponent(props.domain)}/clamav-scan`)
    ])
    clamInstalled.value = !!clam.installed
    lastScan.value = site.lastScan ?? null
    activeScan.value = site.activeScan ?? null
    globalScanRunning.value = !!site.globalScanRunning
    domainScanRunning.value = site.activeScan?.status === 'running'
    polling.value = domainScanRunning.value
  } catch {
    clamInstalled.value = false
  } finally {
    precheckPending.value = false
  }
}

const startError = ref('')

async function onStart() {
  if (!canScan.value) return
  starting.value = true
  startError.value = ''
  try {
    const res = await $fetch<{ scanId?: string; accepted?: boolean; message?: string }>(
      `/api/websites/${encodeURIComponent(props.domain)}/clamav-scan`,
      { method: 'POST' }
    )
    if (!res.accepted || !res.scanId) {
      throw new Error(res.message || 'Could not start scan')
    }
    polling.value = true
    domainScanRunning.value = true
    emit('started', res.scanId)
    emit('close')
  } catch (e: unknown) {
    startError.value = e instanceof Error ? e.message : 'Could not start scan'
  } finally {
    starting.value = false
  }
}

function formatTime(iso: string) {
  try {
    return new Date(iso).toLocaleString()
  } catch {
    return iso
  }
}

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) precheck()
  }
)
</script>

<style scoped>
.stream-backdrop {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}

.stream-modal {
  width: min(480px, 100%);
  max-height: 90vh;
  overflow: auto;
}

.stream-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 1rem;
}

.stream-header h2 {
  margin: 0;
  font-size: 1.125rem;
}

.stream-sub {
  margin: 0.25rem 0 0;
  font-size: 0.875rem;
  color: var(--muted);
}

.last-scan {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
  margin: 1rem 0;
}

.last-scan dt {
  font-size: 0.75rem;
  color: var(--muted);
}

.last-scan dd {
  margin: 0;
  font-weight: 600;
}

.badge-ok {
  color: var(--success, #16a34a);
}

.badge-warn {
  color: var(--warning, #ca8a04);
}

.badge-error {
  color: var(--danger, #dc2626);
}

.badge-running {
  color: var(--accent);
}

.link-inline {
  color: var(--accent);
  margin-left: 0.25rem;
}

.scan-progress {
  font-size: 0.875rem;
  margin: 0.75rem 0 0;
}

.stream-footer {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  justify-content: flex-end;
  margin-top: 1.25rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
}

.muted {
  color: var(--muted);
  font-size: 0.875rem;
}
</style>
