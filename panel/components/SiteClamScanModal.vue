<template>
  <Teleport to="body">
    <div v-if="open" class="stream-backdrop" @click.self="onClose">
      <div class="stream-modal card" role="dialog" aria-modal="true" aria-labelledby="clam-scan-title">
        <header class="stream-header">
          <div>
            <h2 id="clam-scan-title">Scan Virus</h2>
            <p class="stream-sub">{{ targetLabel }}</p>
          </div>
          <button type="button" class="btn btn-ghost btn-sm" @click="onClose">Close</button>
        </header>

        <div v-if="precheckPending" class="precheck-skel" aria-busy="true">
          <div class="status-box" aria-hidden="true">
            <span class="skeleton" style="width: 0.55rem; height: 0.55rem; border-radius: 50%; margin-top: 0.35rem; flex-shrink: 0" />
            <div style="flex: 1">
              <span class="skeleton skeleton-line" style="width: 40%; margin-bottom: 0.5rem" />
              <span class="skeleton skeleton-line" style="width: 90%; margin-bottom: 0.35rem" />
              <span class="skeleton skeleton-line" style="width: 70%" />
            </div>
          </div>
        </div>

        <template v-else>
          <div v-if="!clamInstalled" class="alert alert-warn">
            ClamAV is not installed on this VPS.
            <NuxtLink to="/settings/clamav" class="link-inline">Install from Settings → ClamAV</NuxtLink>
          </div>

          <div v-else-if="otherScanRunning" class="alert alert-warn">
            Another scan is running
            (<code>{{ foreignTargetLabel }}</code>). Wait for it to finish.
          </div>

          <div v-else-if="isAllTarget && !isRunning && !sessionResult" class="alert alert-warn">
            Full <code>apps/</code> scans are CPU/RAM heavy. Prefer a single site on small VPS.
          </div>

          <div v-if="isRunning" class="status-box status-box--running" role="status">
            <span class="progress-dot" aria-hidden="true" />
            <div>
              <strong>Scan in progress</strong>
              <p class="muted">
                Running in the background. You can close this dialog — results also appear under
                <NuxtLink to="/settings/clamav?tab=results" class="link-inline">Settings → ClamAV → Results</NuxtLink>.
              </p>
            </div>
          </div>

          <div
            v-else-if="sessionResult"
            class="status-box"
            :class="resultBoxClass(sessionResult)"
            role="status"
          >
            <div>
              <strong>{{ resultTitle(sessionResult) }}</strong>
              <p class="muted">{{ resultDetail(sessionResult) }}</p>
              <ul v-if="sessionResult.infected?.length" class="hit-list">
                <li v-for="(h, i) in sessionResult.infected.slice(0, 8)" :key="i">
                  <code>{{ h.relPath || h.path }}</code>
                </li>
                <li v-if="sessionResult.infected.length > 8" class="muted">
                  +{{ sessionResult.infected.length - 8 }} more — see Results
                </li>
              </ul>
            </div>
          </div>

          <dl v-else-if="lastScan && clamInstalled && !otherScanRunning" class="last-scan">
            <div>
              <dt>Last scan</dt>
              <dd>{{ formatTime(lastScan.finishedAt || lastScan.startedAt) }}</dd>
            </div>
            <div>
              <dt>Result</dt>
              <dd>
                <span v-if="lastScan.status === 'error'" class="badge-error">Error</span>
                <span v-else-if="(lastScan.infectedCount ?? 0) > 0" class="badge-warn">
                  {{ lastScan.infectedCount }} infected
                </span>
                <span v-else class="badge-ok">No infections</span>
              </dd>
            </div>
          </dl>

          <p
            v-else-if="clamInstalled && !otherScanRunning && !isRunning"
            class="muted intro-empty"
          >
            {{ isAllTarget ? 'No recent full-tree scan in this dialog yet.' : 'No scan recorded for this site yet.' }}
          </p>

          <p v-if="startError" class="alert alert-error">{{ startError }}</p>
        </template>

        <footer class="stream-footer">
          <NuxtLink
            v-if="sessionResult || isRunning"
            to="/settings/clamav?tab=results"
            class="btn btn-ghost btn-sm"
            @click="onClose"
          >
            All results
          </NuxtLink>
          <button type="button" class="btn btn-ghost btn-sm" @click="onClose">
            {{ isRunning ? 'Close' : sessionResult ? 'Done' : 'Cancel' }}
          </button>
          <button
            type="button"
            class="btn btn-primary"
            :disabled="!canScan || starting"
            @click="onStart"
          >
            {{ primaryLabel }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import type { ClamavScanDetail, ClamavScanSummary } from '~/composables/useClamavScan'

const props = defineProps<{
  open: boolean
  /** Site domain, or empty/null to scan all apps */
  domain?: string | null
}>()

const emit = defineEmits<{
  close: []
  started: [scanId: string]
  completed: [scan: ClamavScanDetail | ClamavScanSummary]
}>()

const clamInstalled = ref(false)
const precheckPending = ref(false)
const lastScan = ref<ClamavScanSummary | null>(null)
const foreignActive = ref<ClamavScanSummary | null>(null)
const starting = ref(false)
const startError = ref('')
const sessionResult = ref<ClamavScanDetail | null>(null)
const sessionScanId = ref<string | null>(null)

const normalizedDomain = computed(() => {
  const d = props.domain?.trim().toLowerCase() || ''
  return d || null
})

const isAllTarget = computed(() => !normalizedDomain.value)

const targetLabel = computed(() =>
  isAllTarget.value ? 'All apps under apps/' : normalizedDomain.value || ''
)

const {
  polling,
  activeScan,
  startScan,
  startPoll,
  stopPoll,
  fetchActive
} = useClamavScan({
  onComplete: (scan) => {
    sessionResult.value = scan as ClamavScanDetail
    lastScan.value = scan
    emit('completed', scan)
  }
})

const isOurRunning = computed(() => {
  const a = activeScan.value
  if (!a || a.status !== 'running') return false
  if (sessionScanId.value && a.id === sessionScanId.value) return true
  if (isAllTarget.value) return a.target === 'all' || !a.domain
  return a.target === normalizedDomain.value || a.domain === normalizedDomain.value
})

const isRunning = computed(() => polling.value || isOurRunning.value)

const otherScanRunning = computed(() => {
  if (isRunning.value) return false
  const a = foreignActive.value
  return !!a && a.status === 'running'
})

const foreignTargetLabel = computed(() => {
  const t = foreignActive.value?.target
  if (!t || t === 'all') return 'all apps'
  return t
})

const canScan = computed(
  () =>
    clamInstalled.value &&
    !otherScanRunning.value &&
    !isRunning.value &&
    !starting.value &&
    !precheckPending.value
)

const primaryLabel = computed(() => {
  if (starting.value) return 'Starting…'
  if (isRunning.value) return 'Scanning…'
  if (sessionResult.value || lastScan.value) return 'Scan again'
  return 'Start scan'
})

function resultBoxClass(scan: ClamavScanSummary) {
  if (scan.status === 'error') return 'status-box--error'
  if ((scan.infectedCount ?? 0) > 0) return 'status-box--warn'
  return 'status-box--ok'
}

function resultTitle(scan: ClamavScanSummary) {
  if (scan.status === 'error') return 'Scan failed'
  if ((scan.infectedCount ?? 0) > 0) return 'Infections found'
  return 'Scan complete'
}

function resultDetail(scan: ClamavScanDetail | ClamavScanSummary) {
  if (scan.status === 'error') return scan.error || 'ClamAV reported an error'
  const n = scan.infectedCount ?? 0
  if (n > 0) return `${n} infected file(s). Review Results for the full list.`
  const finished = scan.finishedAt ? formatTime(scan.finishedAt) : ''
  return finished ? `No infections found · ${finished}` : 'No infections found'
}

async function precheck() {
  precheckPending.value = true
  startError.value = ''
  sessionResult.value = null
  sessionScanId.value = null
  foreignActive.value = null
  try {
    const clam = await $fetch<{
      installed?: boolean
      activeScan?: ClamavScanSummary | null
    }>('/api/security/clamav')
    clamInstalled.value = !!clam.installed

    if (normalizedDomain.value) {
      const site = await $fetch<{
        lastScan?: ClamavScanSummary | null
        activeScan?: ClamavScanSummary | null
        globalScanRunning?: boolean
      }>(`/api/websites/${encodeURIComponent(normalizedDomain.value)}/clamav-scan`)
      lastScan.value = site.lastScan ?? null
      const active = site.activeScan
      const ours =
        active?.status === 'running' &&
        (active.target === normalizedDomain.value || active.domain === normalizedDomain.value)
      if (ours && active?.id) {
        sessionScanId.value = active.id
        startPoll(active.id)
      } else if (site.globalScanRunning && active) {
        foreignActive.value = active
      }
    } else {
      lastScan.value = null
      const active = clam.activeScan ?? (await fetchActive())
      if (active?.status === 'running' && active.id) {
        const ours = active.target === 'all' || !active.domain
        if (ours) {
          sessionScanId.value = active.id
          startPoll(active.id)
        } else {
          foreignActive.value = active
        }
      }
    }
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
  sessionResult.value = null
  try {
    const res = await startScan(
      isAllTarget.value ? undefined : { domain: normalizedDomain.value! }
    )
    if (res.scanId) {
      sessionScanId.value = res.scanId
      emit('started', res.scanId)
    }
  } catch (e: unknown) {
    startError.value = fetchApiErrorMessage(e, 'Could not start scan')
    stopPoll()
  } finally {
    starting.value = false
  }
}

function onClose() {
  emit('close')
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
  width: min(520px, 100%);
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
  display: flex;
  align-items: flex-start;
  gap: 0.65rem;
  margin: 0.75rem 0 0;
  padding: 0.85rem 1rem;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--bg-subtle);
}

.status-box--running {
  border-color: color-mix(in srgb, var(--accent) 35%, var(--border));
}

.status-box--ok {
  border-color: color-mix(in srgb, var(--success, #16a34a) 40%, var(--border));
}

.status-box--warn {
  border-color: color-mix(in srgb, var(--warning, #ca8a04) 45%, var(--border));
}

.status-box--error {
  border-color: color-mix(in srgb, var(--danger, #dc2626) 40%, var(--border));
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

.progress-dot {
  width: 0.55rem;
  height: 0.55rem;
  margin-top: 0.35rem;
  border-radius: 50%;
  background: var(--accent);
  flex-shrink: 0;
  animation: pulse 1.2s ease-in-out infinite;
}

.hit-list {
  margin: 0.6rem 0 0;
  padding-left: 1.1rem;
  font-size: 0.75rem;
  line-height: 1.45;
}

.hit-list code {
  font-size: 0.72rem;
  word-break: break-all;
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

.link-inline {
  color: var(--accent);
}

.intro-empty {
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

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
}
</style>
