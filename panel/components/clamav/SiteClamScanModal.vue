<template>
  <Teleport to="body">
    <div v-if="open" class="stream-backdrop" @click.self="emit('close')">
      <div class="stream-modal card" role="dialog" aria-modal="true" aria-labelledby="clam-scan-title">
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

          <div v-else-if="otherScanRunning" class="alert alert-warn">
            Another scan is running
            (<code>{{ activeScan?.target === 'all' ? 'all apps' : activeScan?.target }}</code>).
            Wait for it to finish.
          </div>

          <div v-else-if="domainScanRunning || polling" class="status-box status-box--running">
            <strong>Scan in progress</strong>
            <p class="muted">
              Running in the background. You can close this dialog and check back — results also appear under
              <NuxtLink to="/settings/clamav?tab=results" class="link-inline">Settings → ClamAV → Results</NuxtLink>.
            </p>
          </div>

          <dl v-if="lastScan && !domainScanRunning && !polling" class="last-scan">
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
          <p v-else-if="clamInstalled && !otherScanRunning && !domainScanRunning && !polling" class="muted">
            No scan recorded for this site yet.
          </p>

          <p v-if="startError" class="alert alert-error">{{ startError }}</p>
        </template>

        <footer class="stream-footer">
          <NuxtLink to="/settings/clamav?tab=results" class="btn btn-ghost btn-sm">All results</NuxtLink>
          <button type="button" class="btn btn-ghost btn-sm" @click="emit('close')">
            {{ domainScanRunning || polling ? 'Close' : 'Cancel' }}
          </button>
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
  </Teleport>
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
const startError = ref('')

const otherScanRunning = computed(
  () => globalScanRunning.value && !domainScanRunning.value && !polling.value
)

const canScan = computed(
  () =>
    clamInstalled.value &&
    !globalScanRunning.value &&
    !domainScanRunning.value &&
    !polling.value &&
    !starting.value &&
    !precheckPending.value
)

async function precheck() {
  if (!props.domain) return
  precheckPending.value = true
  startError.value = ''
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
    const runningThis =
      site.activeScan?.status === 'running' &&
      (site.activeScan.target === props.domain || site.activeScan.domain === props.domain)
    domainScanRunning.value = runningThis
    polling.value = runningThis
  } catch (e: unknown) {
    clamInstalled.value = false
    startError.value = fetchApiErrorMessage(e, 'Could not check ClamAV status')
  } finally {
    precheckPending.value = false
  }
}

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
    globalScanRunning.value = true
    activeScan.value = {
      id: res.scanId,
      target: props.domain,
      domain: props.domain,
      scanPath: `apps/${props.domain}`,
      status: 'running',
      startedAt: new Date().toISOString()
    }
    emit('started', res.scanId)
  } catch (e: unknown) {
    startError.value = fetchApiErrorMessage(e, 'Could not start scan')
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
    if (isOpen) void precheck()
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

.status-box {
  margin: 0.75rem 0 0;
  padding: 0.85rem 1rem;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--bg-subtle);
}

.status-box--running {
  border-color: color-mix(in srgb, var(--accent) 35%, var(--border));
}

.status-box strong {
  display: block;
  margin-bottom: 0.35rem;
  font-size: 0.875rem;
}

.status-box p {
  margin: 0;
  font-size: 0.8125rem;
  line-height: 1.45;
}

.last-scan {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.75rem;
  margin: 1rem 0 0;
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
