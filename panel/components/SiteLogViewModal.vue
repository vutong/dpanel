<template>
  <div v-if="open" class="stream-backdrop" @click.self="emit('close')">
    <div class="stream-modal" role="dialog" aria-labelledby="log-view-title">
      <header class="stream-header">
        <div>
          <h2 id="log-view-title">View logs</h2>
          <p class="stream-sub">{{ domain }}</p>
        </div>
        <div class="stream-header-actions">
          <button type="button" class="btn btn-ghost btn-sm" :disabled="clearing" @click="refreshNow">
            Refresh
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            :disabled="!logText || clearing"
            @click="copyLog"
          >
            {{ copyFeedback || 'Copy' }}
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm btn-danger-text"
            :disabled="clearing"
            @click="clearLog"
          >
            {{ clearing ? 'Clearing…' : 'Clear log' }}
          </button>
        </div>
      </header>

      <div class="log-tabs" role="tablist">
        <button
          v-for="t in tabs"
          :key="t.id"
          type="button"
          role="tab"
          class="log-tab"
          :class="{ active: activeTab === t.id }"
          :aria-selected="activeTab === t.id"
          @click="setTab(t.id)"
        >
          {{ t.label }}
        </button>
      </div>

      <p class="stream-status-msg">{{ tabHint }}</p>
      <p v-if="clearedNotice" class="stream-status-msg stream-status-msg--ok">{{ clearedNotice }}</p>

      <div ref="logViewport" class="stream-log">
        <pre class="stream-pre">{{ logText || emptyHint }}</pre>
      </div>

      <footer class="stream-footer">
        <button type="button" class="btn btn-ghost btn-sm" :disabled="!logText || clearing" @click="copyLog">
          Copy log
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-sm btn-danger-text"
          :disabled="clearing"
          @click="clearLog"
        >
          Clear log
        </button>
        <button type="button" class="btn btn-primary" @click="emit('close')">Close</button>
      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
type SiteLogKind = 'rebuild' | 'update' | 'create' | 'container'

const props = defineProps<{
  open: boolean
  domain: string
}>()

const emit = defineEmits<{ close: [] }>()

const tabs: { id: SiteLogKind; label: string }[] = [
  { id: 'container', label: 'App' },
  { id: 'rebuild', label: 'Rebuild' },
  { id: 'update', label: 'Git pull' },
  { id: 'create', label: 'Create' }
]

const activeTab = ref<SiteLogKind>('container')
const logText = ref('')
const logOffset = ref(0)
const initialLoad = ref(false)
const clearing = ref(false)
const clearedNotice = ref('')
const logPaused = ref(false)
const logViewport = ref<HTMLElement | null>(null)
const { copyFeedback, copyText } = useCopyText()

function copyLog() {
  void copyText(logText.value)
}

let pollTimer: ReturnType<typeof setInterval> | undefined
let pollGen = 0

const tabHint = computed(() => {
  if (logPaused.value && activeTab.value === 'container') {
    return 'Auto-refresh paused after clear — click Refresh to load new App logs'
  }
  const map: Record<SiteLogKind, string> = {
    container: 'Docker logs (last 400 lines) — refreshes every 3s',
    rebuild: 'logs/node/site-rebuild-*.log',
    update: 'logs/node/site-update-*.log',
    create: 'logs/node/site-create-*.log'
  }
  return map[activeTab.value]
})

const emptyHint = computed(() =>
  initialLoad.value ? 'Loading…' : 'No log output yet for this source.'
)

function scrollLogToEnd() {
  nextTick(() => {
    const el = logViewport.value
    if (el) el.scrollTop = el.scrollHeight
  })
}

function resetLog() {
  logText.value = ''
  logOffset.value = 0
}

function setTab(id: SiteLogKind) {
  if (activeTab.value === id) return
  activeTab.value = id
  clearedNotice.value = ''
  logPaused.value = false
  resetLog()
  void fetchLog(true)
  startPolling()
}

async function fetchLog(showSpinner = false) {
  const gen = pollGen
  if (showSpinner) initialLoad.value = true
  try {
    const res = await $fetch<{
      chunk: string
      offset: number
      full?: boolean
    }>(`/api/websites/${encodeURIComponent(props.domain)}/log`, {
      query: {
        op: activeTab.value,
        offset: activeTab.value === 'container' || logOffset.value === 0 ? 0 : logOffset.value
      }
    })
    if (gen !== pollGen) return

    if (res.full || activeTab.value === 'container') {
      logText.value = res.chunk
      logOffset.value = res.offset
    } else if (res.chunk) {
      if (logOffset.value === 0) {
        logText.value = res.chunk
      } else {
        logText.value += res.chunk
      }
      logOffset.value = res.offset
    }
    scrollLogToEnd()
  } catch {
    if (gen === pollGen) logText.value = '[dpanel] Could not load logs.'
  } finally {
    if (gen === pollGen && showSpinner) initialLoad.value = false
  }
}

function refreshNow() {
  clearedNotice.value = ''
  logPaused.value = false
  resetLog()
  void fetchLog(true)
  startPolling()
}

async function clearLog() {
  if (clearing.value) return
  const tab = tabs.find((t) => t.id === activeTab.value)?.label ?? activeTab.value
  if (!import.meta.client || !confirm(`Clear ${tab} log for ${props.domain}? This cannot be undone.`)) {
    return
  }

  clearing.value = true
  clearedNotice.value = ''
  stopPolling()

  try {
    await $fetch(`/api/websites/${encodeURIComponent(props.domain)}/log`, {
      method: 'DELETE',
      query: { op: activeTab.value }
    })
    resetLog()
    if (activeTab.value === 'container') {
      logPaused.value = true
      logText.value = '(Log cleared — app may write new lines; click Refresh to view.)'
      clearedNotice.value = 'Docker log cleared. Auto-refresh paused until you click Refresh.'
    } else {
      clearedNotice.value = 'Log file cleared.'
      await fetchLog(false)
      startPolling()
    }
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    logText.value =
      err.data?.statusMessage || err.statusMessage || '[dpanel] Could not clear log.'
    startPolling()
  } finally {
    clearing.value = false
  }
}

function startPolling() {
  if (logPaused.value) return
  stopPolling(false)
  pollTimer = setInterval(() => void fetchLog(false), 3000)
}

function stopPolling(bumpGen = true) {
  if (bumpGen) pollGen += 1
  if (pollTimer) clearInterval(pollTimer)
  pollTimer = undefined
}

function startSession() {
  stopPolling()
  pollGen += 1
  resetLog()
  clearedNotice.value = ''
  logPaused.value = false
  activeTab.value = 'container'
  void fetchLog(true)
  startPolling()
}

watch(
  () => [props.open, props.domain] as const,
  ([isOpen]) => {
    if (isOpen) startSession()
    else stopPolling()
  },
  { immediate: true }
)

onUnmounted(() => stopPolling())
</script>

<style scoped>
.stream-backdrop {
  position: fixed;
  inset: 0;
  z-index: 195;
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
  padding: 1rem 1.15rem 0.5rem;
  border-bottom: 1px solid #21262d;
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

.stream-header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-shrink: 0;
}

.log-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  padding: 0.5rem 1rem 0;
}

.log-tab {
  border: 1px solid #30363d;
  background: #161b22;
  color: #8b949e;
  border-radius: 6px;
  padding: 0.3rem 0.65rem;
  font-size: 0.78rem;
  cursor: pointer;
}

.log-tab:hover {
  color: #c9d1d9;
  border-color: #484f58;
}

.log-tab.active {
  background: rgba(79, 143, 247, 0.15);
  border-color: #388bfd;
  color: #79b8ff;
}

.stream-status-msg {
  margin: 0;
  padding: 0.35rem 1.15rem 0;
  font-size: 0.78rem;
  color: #8b949e;
}

.stream-status-msg--ok {
  color: #3fb950;
}

.stream-log {
  flex: 1;
  min-height: 260px;
  margin: 0.65rem 1rem;
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

.btn-danger-text {
  color: #f85149;
}

.btn-danger-text:hover:not(:disabled) {
  color: #ff7b72;
  border-color: rgba(248, 81, 73, 0.45);
}
</style>
