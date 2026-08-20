<template>
  <div v-if="open" class="stream-backdrop" @click.self="onBackdropClick">
    <div class="stream-modal" role="dialog" :aria-labelledby="titleId">
      <header class="stream-header">
        <div>
          <h2 :id="titleId">{{ title }}</h2>
          <p class="stream-sub">{{ domain }}</p>
        </div>
        <div class="stream-header-actions">
          <span class="stream-badge" :class="badgeClass">{{ statusLabel }}</span>
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            :disabled="!logText"
            @click="copyLog"
          >
            {{ copyFeedback || 'Copy' }}
          </button>
        </div>
      </header>

      <p v-if="statusMessage" class="stream-status-msg">{{ statusMessage }}</p>
      <p v-if="phase === 'error'" class="stream-status-msg stream-status-msg--err">
        Operation failed — review the log below, then close when done.
      </p>

      <div ref="logViewport" class="stream-log">
        <pre class="stream-pre">{{ logText || waitingHint }}</pre>
      </div>

      <footer class="stream-footer">
        <button
          v-if="phase === 'running'"
          type="button"
          class="btn btn-ghost"
          @click="emit('close')"
        >
          Run in background
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          :disabled="!logText"
          @click="copyLog"
        >
          Copy log
        </button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="phase === 'running'"
          @click="onCloseClick"
        >
          {{ closeLabel }}
        </button>
      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
export type SiteOpKind = 'update' | 'rebuild' | 'fix-permissions'

type SiteOpStatus = {
  op?: string
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
  updatedAt?: string
}

const props = defineProps<{
  open: boolean
  domain: string
  op: SiteOpKind
}>()

const emit = defineEmits<{
  close: []
  done: [payload: { ok: boolean; message: string }]
}>()

const titleId = `site-op-${Math.random().toString(36).slice(2, 9)}`
const logText = ref('')
const logOffset = ref(0)
const statusMessage = ref('')
const phase = ref<'running' | 'ok' | 'error'>('running')

let logTimer: ReturnType<typeof setInterval> | undefined
let statusTimer: ReturnType<typeof setInterval> | undefined
let pollGen = 0
/** Ignore terminal status written before this stream started (stale after a failed run). */
let streamStartedAtMs = 0
let sawRunningForStream = false
const logViewport = ref<HTMLElement | null>(null)

const title = computed(() => {
  if (props.op === 'rebuild') return 'Rebuild'
  if (props.op === 'fix-permissions') return 'Fix permissions'
  return 'Update from Git'
})

const statusLabel = computed(() => {
  if (phase.value === 'ok') return 'Complete'
  if (phase.value === 'error') return 'Failed'
  return 'Running'
})

const badgeClass = computed(() => ({
  'stream-badge--ok': phase.value === 'ok',
  'stream-badge--err': phase.value === 'error',
  'stream-badge--run': phase.value === 'running'
}))

const waitingHint = computed(() =>
  phase.value === 'running'
    ? 'Waiting for log output from the server…'
    : ''
)

const closeLabel = computed(() => {
  if (phase.value === 'running') return 'Please wait…'
  if (phase.value === 'error') return 'Close'
  return 'Close'
})

const { copyFeedback, copyText } = useCopyText()

function copyLog() {
  void copyText(logText.value)
}

function scrollLogToEnd() {
  nextTick(() => {
    const el = logViewport.value
    if (el) el.scrollTop = el.scrollHeight
  })
}

async function fetchLogChunk() {
  const res = await $fetch<{
    offset: number
    chunk: string
  }>(`/api/websites/${encodeURIComponent(props.domain)}/log`, {
    query: { op: props.op, offset: logOffset.value }
  })
  if (res.chunk) {
    logText.value += res.chunk
    logOffset.value = res.offset
    scrollLogToEnd()
  }
}

async function fetchStatus() {
  const s = await $fetch<SiteOpStatus>(
    `/api/websites/${encodeURIComponent(props.domain)}/operation`
  )
  if (s.op && s.op !== props.op) return
  if (s.message) statusMessage.value = s.message
  if (s.status === 'running') {
    sawRunningForStream = true
    return
  }
  if (s.status === 'none') return

  const updatedAtMs = s.updatedAt ? Date.parse(s.updatedAt) : NaN
  const isFresh =
    sawRunningForStream ||
    (!Number.isNaN(updatedAtMs) && updatedAtMs >= streamStartedAtMs - 1500)
  // Stale ok/error from a previous hung/failed run — keep waiting for this run.
  if (!isFresh) return

  phase.value = s.status === 'ok' ? 'ok' : 'error'
  stopTimers()
  await fetchLogChunk()
  const msg =
    s.message ||
    (s.status === 'ok'
      ? props.op === 'rebuild'
        ? 'Rebuild complete'
        : props.op === 'fix-permissions'
          ? 'Permissions fixed'
          : 'Pull complete'
      : 'Operation failed')
  emit('done', { ok: s.status === 'ok', message: `${props.domain}: ${msg}` })
}

function stopTimers() {
  if (logTimer) clearInterval(logTimer)
  if (statusTimer) clearInterval(statusTimer)
  logTimer = undefined
  statusTimer = undefined
}

function startStreaming() {
  stopTimers()
  pollGen += 1
  const gen = pollGen
  streamStartedAtMs = Date.now()
  sawRunningForStream = false
  logText.value = ''
  logOffset.value = 0
  statusMessage.value =
    props.op === 'rebuild'
      ? 'Starting rebuild…'
      : props.op === 'fix-permissions'
        ? 'Fixing permissions…'
        : 'Pulling from Git…'
  phase.value = 'running'

  void fetchLogChunk()
  void fetchStatus()
  logTimer = setInterval(() => {
    if (gen !== pollGen) return
    void fetchLogChunk().catch(() => {})
  }, 1200)
  statusTimer = setInterval(() => {
    if (gen !== pollGen) return
    void fetchStatus().catch(() => {})
  }, 2000)
}

function onCloseClick() {
  if (phase.value === 'running') return
  emit('close')
}

function onBackdropClick() {
  if (phase.value === 'ok') emit('close')
}

watch(
  () => [props.open, props.domain, props.op] as const,
  ([isOpen]) => {
    if (isOpen) startStreaming()
    else stopTimers()
  },
  { immediate: true }
)

onUnmounted(stopTimers)
</script>

<style scoped>
.stream-backdrop {
  position: fixed;
  inset: 0;
  z-index: 200;
  background: rgba(0, 0, 0, 0.72);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}

.stream-modal {
  width: 100%;
  max-width: 720px;
  max-height: min(88vh, 720px);
  display: flex;
  flex-direction: column;
  background: #0a0e14;
  border: 1px solid #2a3548;
  border-radius: 12px;
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.65);
  color: #e6edf3;
}

.stream-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
  padding: 1rem 1.15rem 0.65rem;
  border-bottom: 1px solid #21262d;
}

.stream-header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-shrink: 0;
}

.stream-status-msg--err {
  color: #f85149 !important;
}

.stream-header h2 {
  font-size: 1.05rem;
  font-weight: 600;
  margin: 0;
}

.stream-sub {
  margin: 0.2rem 0 0;
  font-size: 0.82rem;
  color: #8b949e;
  word-break: break-all;
}

.stream-badge {
  font-size: 0.72rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.25rem 0.55rem;
  border-radius: 6px;
  flex-shrink: 0;
}

.stream-badge--run {
  background: rgba(79, 143, 247, 0.18);
  color: #79b8ff;
}

.stream-badge--ok {
  background: rgba(34, 197, 94, 0.18);
  color: #3fb950;
}

.stream-badge--err {
  background: rgba(239, 68, 68, 0.18);
  color: #f85149;
}

.stream-status-msg {
  margin: 0;
  padding: 0.5rem 1.15rem 0;
  font-size: 0.85rem;
  color: #8b949e;
}

.stream-log {
  flex: 1;
  min-height: 280px;
  margin: 0.75rem 1rem;
  padding: 0.75rem;
  background: #010409;
  border: 1px solid #21262d;
  border-radius: 8px;
  overflow: auto;
}

.stream-pre {
  margin: 0;
  font-family: ui-monospace, 'Cascadia Code', 'Consolas', monospace;
  font-size: 0.78rem;
  line-height: 1.45;
  color: #c9d1d9;
  white-space: pre-wrap;
  word-break: break-word;
}

.stream-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  padding: 0.75rem 1rem 1rem;
  border-top: 1px solid #21262d;
}
</style>
