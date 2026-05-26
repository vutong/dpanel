<template>
  <div v-if="open" class="env-backdrop" @click.self="onCancel">
    <div class="env-modal card" role="dialog" aria-labelledby="env-edit-title">
      <header class="env-header">
        <h2 id="env-edit-title">Edit .env</h2>
        <p class="env-sub">
          <code>apps/{{ domain }}/.env</code>
        </p>
      </header>

      <PageLoader v-if="loading" label="Loading .env…" />
      <template v-else>
        <p v-if="loadError" class="alert alert-error">{{ loadError }}</p>
        <div v-else class="field">
          <textarea
            v-model="content"
            class="env-textarea input"
            rows="14"
            spellcheck="false"
            autocomplete="off"
            :disabled="saving"
            placeholder="# MONGODB_URI=&#10;# NUXT_PUBLIC_API_URL="
          />
          <label class="env-restart checkbox-label">
            <input v-model="restartAfterSave" type="checkbox" :disabled="saving" />
            Restart app container after save
          </label>
          <p class="hint">
            Secrets stay on the server in this file. After changing database URLs, enable restart so the app reloads env.
          </p>
        </div>
      </template>

      <footer class="env-footer">
        <button type="button" class="btn btn-ghost" :disabled="saving" @click="onCancel">Cancel</button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="loading || !!loadError || saving"
          @click="onSave"
        >
          {{ saving ? 'Saving…' : 'Save' }}
        </button>
      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  open: boolean
  domain: string
}>()

const emit = defineEmits<{
  close: []
  saved: [payload: { restarted: boolean }]
}>()

const content = ref('')
const loading = ref(false)
const saving = ref(false)
const loadError = ref('')
const restartAfterSave = ref(true)

async function loadEnv() {
  loading.value = true
  loadError.value = ''
  content.value = ''
  try {
    const res = await $fetch<{ content?: string }>(
      `/api/websites/${encodeURIComponent(props.domain)}/env`
    )
    content.value = res.content ?? ''
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Could not load .env'
  } finally {
    loading.value = false
  }
}

async function onSave() {
  saving.value = true
  try {
    const res = await $fetch<{ restarted?: boolean }>(
      `/api/websites/${encodeURIComponent(props.domain)}/env`,
      {
        method: 'PUT',
        body: { content: content.value, restart: restartAfterSave.value }
      }
    )
    emit('saved', { restarted: !!res.restarted })
    emit('close')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Could not save .env'
  } finally {
    saving.value = false
  }
}

function onCancel() {
  if (!saving.value) emit('close')
}

watch(
  () => [props.open, props.domain] as const,
  ([isOpen, domain]) => {
    if (isOpen && domain) void loadEnv()
  },
  { immediate: true }
)
</script>

<style scoped>
.env-backdrop {
  position: fixed;
  inset: 0;
  z-index: 190;
  background: rgba(0, 0, 0, 0.65);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}

.env-modal {
  width: 100%;
  max-width: 640px;
  max-height: min(90vh, 720px);
  display: flex;
  flex-direction: column;
}

.env-header {
  margin-bottom: 0.75rem;
}

.env-header h2 {
  font-size: 1.1rem;
  margin: 0 0 0.25rem;
}

.env-sub {
  margin: 0;
  font-size: 0.82rem;
  color: var(--muted);
}

.env-sub code {
  font-size: 0.8rem;
}

.env-textarea {
  width: 100%;
  font-family: ui-monospace, 'Cascadia Code', 'Consolas', monospace;
  font-size: 0.8rem;
  line-height: 1.45;
  resize: vertical;
  min-height: 280px;
}

.env-restart {
  margin-top: 0.75rem;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 500;
  cursor: pointer;
  font-size: 0.9rem;
}

.checkbox-label input {
  width: auto;
}

.hint {
  margin: 0.5rem 0 0;
  font-size: 0.8rem;
  color: var(--muted);
  line-height: 1.45;
}

.env-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
  padding-top: 0.75rem;
  border-top: 1px solid var(--border);
}
</style>
