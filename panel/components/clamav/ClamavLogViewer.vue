<template>
  <div class="log-viewer">
    <div class="toolbar">
      <label class="field-inline">
        <span class="label-sm">Source</span>
        <select v-model="logSource" class="input input-sm">
          <option value="clamav">clamav.log</option>
          <option value="freshclam">freshclam.log</option>
          <option value="clamd">clamd.log</option>
          <option value="scan">Latest panel scan</option>
        </select>
      </label>
      <label class="field-inline">
        <span class="label-sm">Lines</span>
        <select v-model.number="lineCount" class="input input-sm">
          <option :value="100">100</option>
          <option :value="200">200</option>
          <option :value="500">500</option>
        </select>
      </label>
      <input
        v-model="grep"
        type="search"
        class="input search"
        placeholder="Filter…"
        @keydown.enter="load"
      />
      <button type="button" class="btn btn-sm" :disabled="loading" @click="load">
        {{ loading ? 'Loading…' : 'Refresh' }}
      </button>
      <span v-if="path" class="path muted">{{ path }}</span>
    </div>

    <PageLoader v-if="loading && !lines.length" label="Loading logs…" />

    <div v-else-if="warning" class="card muted warn">{{ warning }}</div>

    <div v-else class="card log-box">
      <pre class="log-pre"><code v-for="(line, i) in lines" :key="i">{{ line }}
</code></pre>
      <p v-if="!lines.length" class="muted empty">No log lines.</p>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  installed: boolean
}>()

const lineCount = ref(200)
const grep = ref('')
const logSource = ref('clamav')
const lines = ref<string[]>([])
const path = ref<string | null>(null)
const warning = ref('')
const loading = ref(false)

async function load() {
  if (!props.installed) return
  loading.value = true
  warning.value = ''
  try {
    const q = new URLSearchParams({
      lines: String(lineCount.value),
      source: logSource.value
    })
    if (grep.value.trim()) q.set('grep', grep.value.trim())
    const res = await $fetch<{
      ok?: boolean
      error?: string
      lines?: string[]
      path?: string | null
      warning?: string
    }>(`/api/security/clamav/logs?${q}`)
    if (res.ok === false) {
      warning.value = res.error || 'Could not load logs'
      lines.value = []
      path.value = null
      return
    }
    lines.value = res.lines ?? []
    path.value = res.path ?? null
    warning.value = res.warning ?? ''
  } catch (e: unknown) {
    warning.value = fetchApiErrorMessage(e, 'Could not load logs')
    lines.value = []
  } finally {
    loading.value = false
  }
}

watch(
  () => [props.installed, logSource.value],
  ([inst]) => {
    if (inst) load()
  },
  { immediate: true }
)

defineExpose({ load })
</script>

<style scoped>
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
  font-size: 0.8125rem;
  color: var(--muted);
}

.input-sm {
  width: auto;
  min-width: 4.5rem;
}

.search {
  min-width: 180px;
  flex: 1;
  max-width: 280px;
}

.path {
  font-size: 0.75rem;
  font-family: var(--font-mono, monospace);
}

.log-box {
  padding: 0;
  overflow: hidden;
}

.log-pre {
  margin: 0;
  padding: 0.75rem 1rem;
  max-height: 420px;
  overflow: auto;
  font-size: 0.75rem;
  line-height: 1.45;
  background: var(--surface-2);
}

.log-pre code {
  display: block;
  white-space: pre-wrap;
  word-break: break-all;
  font-family: var(--font-mono, monospace);
}

.empty {
  padding: 0.75rem 1rem;
  margin: 0;
}

.warn {
  padding: 1rem;
  font-size: 0.875rem;
}

.muted {
  color: var(--muted);
}
</style>
