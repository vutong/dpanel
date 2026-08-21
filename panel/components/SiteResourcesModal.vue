<template>
  <div v-if="open" class="res-backdrop" @click.self="onCancel">
    <div class="res-modal card" role="dialog" aria-labelledby="res-title">
      <header class="res-header">
        <h2 id="res-title">Resource limits</h2>
        <p class="res-sub">
          Docker limits for <strong>{{ domain }}</strong>. Use <code>0</code> for no limit.
          Disk quota is best-effort (depends on storage driver).
        </p>
      </header>

      <div v-if="loading" aria-busy="true">
        <div class="usage-line" aria-hidden="true">
          <span class="skeleton skeleton-line-sm" style="width: 6rem" />
          <span class="skeleton skeleton-line" style="width: 40%" />
        </div>
        <div class="field" aria-hidden="true">
          <span class="skeleton skeleton-line-sm" style="width: 5rem; margin-bottom: 0.4rem" />
          <span class="skeleton skeleton-block" style="height: 2.25rem; margin-bottom: 0.85rem" />
          <span class="skeleton skeleton-line-sm" style="width: 5.5rem; margin-bottom: 0.4rem" />
          <span class="skeleton skeleton-block" style="height: 2.25rem; margin-bottom: 0.85rem" />
          <span class="skeleton skeleton-line-sm" style="width: 5rem; margin-bottom: 0.4rem" />
          <span class="skeleton skeleton-block" style="height: 2.25rem" />
        </div>
      </div>
      <template v-else>
        <p v-if="loadError" class="alert alert-error">{{ loadError }}</p>
        <template v-else>
          <div v-if="appDirBytes != null" class="usage-line">
            <span class="label">App folder usage</span>
            <span>{{ formatBytes(appDirBytes) }} <span class="muted-inline">apps/{{ domain }}/</span></span>
          </div>

          <div class="field">
            <label class="label" for="cpu-limit">Max CPU cores</label>
            <input
              id="cpu-limit"
              v-model.number="cpuLimit"
              class="input"
              type="number"
              min="0"
              max="64"
              step="0.25"
              :disabled="saving"
            />
          </div>
          <div class="field">
            <label class="label" for="mem-limit">Max RAM (MB)</label>
            <input
              id="mem-limit"
              v-model.number="memoryMb"
              class="input"
              type="number"
              min="0"
              step="64"
              :disabled="saving"
            />
          </div>
          <div class="field">
            <label class="label" for="disk-limit">Max disk (GB)</label>
            <input
              id="disk-limit"
              v-model.number="diskGb"
              class="input"
              type="number"
              min="0"
              step="1"
              :disabled="saving"
            />
            <p class="hint">Applies to the container storage option; folder size may differ.</p>
          </div>
        </template>
      </template>

      <footer class="res-footer">
        <button type="button" class="btn btn-ghost" :disabled="saving" @click="onCancel">Cancel</button>
        <button type="button" class="btn btn-primary" :disabled="saving || loading" @click="save">
          {{ saving ? 'Applying…' : 'Save & apply' }}
        </button>
      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
import { formatBytes } from '~/composables/useFormatBytes'

const props = defineProps<{ open: boolean; domain: string }>()
const emit = defineEmits<{ close: []; saved: [] }>()

const loading = ref(false)
const loaded = ref(false)
const saving = ref(false)
const loadError = ref('')
const cpuLimit = ref(0)
const memoryMb = ref(0)
const diskGb = ref(0)
const appDirBytes = ref<number | null>(null)

watch(
  () => [props.open, props.domain] as const,
  ([open, domain]) => {
    if (open && domain) {
      loaded.value = false
      void load()
    }
  }
)

async function load() {
  if (!props.domain) return
  loading.value = true
  loadError.value = ''
  try {
    const data = await $fetch<{
      config: { cpuLimit: number; memoryMb: number; diskGb: number }
      appDirBytes: number | null
    }>(`/api/websites/${encodeURIComponent(props.domain)}/resources`)
    cpuLimit.value = data.config.cpuLimit
    memoryMb.value = data.config.memoryMb
    diskGb.value = data.config.diskGb
    appDirBytes.value = data.appDirBytes
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Could not load resources'
  } finally {
    loading.value = false
    loaded.value = true
  }
}

function onCancel() {
  if (saving.value) return
  emit('close')
}

async function save() {
  saving.value = true
  loadError.value = ''
  try {
    const data = await $fetch<{
      config: { cpuLimit: number; memoryMb: number; diskGb: number }
      appDirBytes: number | null
    }>(`/api/websites/${encodeURIComponent(props.domain)}/resources`, {
      method: 'PUT',
      body: {
        cpuLimit: Number(cpuLimit.value) || 0,
        memoryMb: Number(memoryMb.value) || 0,
        diskGb: Number(diskGb.value) || 0
      }
    })
    appDirBytes.value = data.appDirBytes
    emit('saved')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Could not save'
  } finally {
    saving.value = false
  }
}
</script>

<style scoped>
.res-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
  padding: 1rem;
}
.res-modal {
  width: 100%;
  max-width: 440px;
}
.res-header h2 {
  font-size: 1.15rem;
  margin-bottom: 0.35rem;
}
.res-sub {
  font-size: 0.85rem;
  color: var(--muted);
  line-height: 1.45;
  margin-bottom: 1rem;
}
.usage-line {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  font-size: 0.88rem;
  margin-bottom: 1rem;
  padding: 0.65rem 0.75rem;
  border-radius: 8px;
  background: var(--bg-subtle);
  border: 1px solid var(--border);
}
.muted-inline {
  color: var(--muted);
  font-size: 0.8rem;
}
.hint {
  font-size: 0.78rem;
  color: var(--muted);
  margin-top: 0.35rem;
}
.res-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1.25rem;
}
</style>
