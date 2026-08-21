<template>
  <div class="log-viewer">
    <div class="toolbar">
      <label class="field-inline">
        <span class="label-sm">Lines</span>
        <select v-model.number="lineCount" class="select select-sm">
          <option :value="100">100</option>
          <option :value="200">200</option>
          <option :value="500">500</option>
        </select>
      </label>
      <input
        v-model="grep"
        type="search"
        class="input search"
        placeholder="Filter (jail or IP)…"
        @keydown.enter="load"
      />
      <button type="button" class="btn btn-ghost btn-sm toolbar-refresh" :disabled="loading" @click="load">
        <AppIcon name="refresh" :size="14" />
        {{ loading ? 'Refreshing…' : 'Refresh' }}
      </button>
      <span v-if="path" class="path muted">{{ path }}</span>
    </div>

    <div v-if="loading" class="card log-box" aria-busy="true">
      <div class="log-skel" aria-hidden="true">
        <div v-for="n in 10" :key="n" class="skeleton-row" style="margin-bottom: 0.45rem">
          <span class="skeleton skeleton-line" :style="{ width: `${55 + (n % 4) * 10}%` }" />
        </div>
      </div>
    </div>

    <div v-else-if="warning" class="card muted warn">{{ warning }}</div>

    <div v-else class="card log-box">
      <pre v-if="lines.length" class="log-pre"><code v-for="(line, i) in lines" :key="i">{{ line }}
</code></pre>
      <p v-else class="muted empty">No log lines.</p>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  installed: boolean
  active: boolean
}>()

const lineCount = ref(200)
const grep = ref('')
const lines = ref<string[]>([])
const path = ref<string | null>(null)
const warning = ref('')
const loading = ref(false)

async function load() {
  if (!props.installed) return
  loading.value = true
  warning.value = ''
  try {
    const q = new URLSearchParams({ lines: String(lineCount.value) })
    if (grep.value.trim()) q.set('grep', grep.value.trim())
    const res = await $fetch<{
      ok?: boolean
      error?: string
      lines?: string[]
      path?: string | null
      warning?: string
    }>(`/api/security/fail2ban/logs?${q}`)
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
  () => [props.installed, props.active],
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
  font-size: var(--text-sm);
  color: var(--muted);
}

.search {
  min-width: 180px;
  flex: 1;
  max-width: 280px;
  padding: 0.28rem 0.6rem;
  font-size: var(--text-xs);
  min-height: var(--control-h-sm);
}

.toolbar-refresh {
  margin-left: auto;
}

.path {
  font-size: 0.75rem;
  font-family: var(--font-mono, monospace);
}

.log-box {
  padding: 0;
  overflow: hidden;
}

.log-skel {
  padding: 0.75rem 1rem;
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
</style>
