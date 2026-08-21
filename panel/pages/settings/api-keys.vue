<template>
  <div>
    <div class="header">
      <h1>API Keys</h1>
      <button type="button" class="btn btn-primary" @click="openCreate">+ Add</button>
    </div>

    <p class="page-desc">
      Machine credentials for apps (domain check, nginx routing). Secrets are shown only once when created.
      Paste <code>DPANEL_API_KEY</code> and <code>DPANEL_API_SECRET</code> into each Node site
      <code>.env</code>.
    </p>

    <div v-if="listLoading" class="card table-wrap" aria-busy="true">
      <table class="table">
        <thead>
          <tr>
            <th>API Key</th>
            <th>API Secret</th>
            <th>API Label</th>
            <th>Permission</th>
            <th class="col-actions">Action</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="n in 4" :key="n" aria-hidden="true">
            <td><span class="skeleton skeleton-line" style="width: 65%" /></td>
            <td><span class="skeleton skeleton-text" style="width: 5rem" /></td>
            <td><span class="skeleton skeleton-line" style="width: 40%" /></td>
            <td><span class="skeleton skeleton-text" style="width: 4.5rem" /></td>
            <td class="col-actions">
              <span class="skeleton skeleton-text" style="width: 2.5rem; margin-left: auto" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-else-if="!keys.length" class="card muted">
      No API keys yet. Create one before apps can sync custom domains or check host availability.
    </div>
    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>API Key</th>
            <th>API Secret</th>
            <th>API Label</th>
            <th>Permission</th>
            <th class="col-actions">Action</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in keys" :key="row.id">
            <td>
              <div class="key-cell">
                <code class="mono">{{ revealed[row.id] ? row.key : maskKey(row.key) }}</code>
                <button
                  type="button"
                  class="icon-btn"
                  :title="revealed[row.id] ? 'Hide' : 'Show'"
                  @click="toggleReveal(row.id)"
                >
                  <AppIcon :name="revealed[row.id] ? 'eye-off' : 'eye'" :size="16" />
                </button>
              </div>
            </td>
            <td>
              <span class="secret-placeholder" title="Shown only once at creation">••••••••••••</span>
            </td>
            <td>
              <div v-if="editingId === row.id" class="label-edit">
                <input
                  v-model="editingLabel"
                  class="input input-inline"
                  maxlength="120"
                  @keydown.enter.prevent="saveLabel(row.id)"
                  @keydown.esc.prevent="cancelEdit"
                />
              </div>
              <span v-else>{{ row.label }}</span>
            </td>
            <td>
              <span class="badge" :class="row.permission === 'read_write' ? 'badge-write' : 'badge-read'">
                {{ permissionLabel(row.permission) }}
              </span>
            </td>
            <td class="col-actions">
              <button
                v-if="editingId === row.id"
                type="button"
                class="icon-btn"
                title="Save"
                :disabled="savingLabel"
                @click="saveLabel(row.id)"
              >
                <AppIcon name="check" :size="16" />
              </button>
              <button
                v-else
                type="button"
                class="icon-btn"
                title="Edit label"
                @click="startEdit(row)"
              >
                <AppIcon name="edit" :size="16" />
              </button>
              <button
                type="button"
                class="icon-btn icon-btn-danger"
                title="Delete"
                :disabled="editingId === row.id"
                @click="confirmDelete(row)"
              >
                <AppIcon name="trash" :size="16" />
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Create modal -->
    <div v-if="createOpen" class="modal-backdrop" @click.self="closeCreate">
      <div class="modal card" role="dialog" aria-labelledby="create-key-title">
        <h2 id="create-key-title">{{ createdPayload ? 'API key created' : 'Add API key' }}</h2>

        <template v-if="!createdPayload">
          <div class="field">
            <label class="label" for="api-label">Label</label>
            <input id="api-label" v-model="createForm.label" class="input" maxlength="120" placeholder="Dutabi production" />
          </div>
          <div class="field">
            <span class="label">Permission</span>
            <label class="radio-row">
              <input v-model="createForm.permission" type="radio" value="read_write" />
              Read &amp; Write — check hosts + sync routing
            </label>
            <label class="radio-row">
              <input v-model="createForm.permission" type="radio" value="read" />
              Read Only — check hosts only
            </label>
          </div>
          <p v-if="createError" class="alert alert-error">{{ createError }}</p>
          <div class="modal-actions">
            <button type="button" class="btn btn-ghost" :disabled="creating" @click="closeCreate">Cancel</button>
            <button type="button" class="btn btn-primary" :disabled="creating" @click="submitCreate">
              {{ creating ? 'Creating…' : 'Create' }}
            </button>
          </div>
        </template>

        <template v-else>
          <p class="warn">
            Copy the secret now. It cannot be shown again.
          </p>
          <div class="field">
            <label class="label">API Key</label>
            <div class="copy-row">
              <code class="mono block">{{ createdPayload.key }}</code>
              <button type="button" class="btn btn-ghost" @click="copyText(createdPayload.key)">Copy</button>
            </div>
          </div>
          <div class="field">
            <label class="label">API Secret</label>
            <div class="copy-row">
              <code class="mono block">{{ createdPayload.secret }}</code>
              <button type="button" class="btn btn-ghost" @click="copyText(createdPayload.secret)">Copy</button>
            </div>
          </div>
          <div class="field">
            <label class="label">.env snippet</label>
            <div class="copy-row">
              <pre class="env-snippet">{{ envSnippet }}</pre>
              <button type="button" class="btn btn-ghost" @click="copyText(envSnippet)">Copy</button>
            </div>
          </div>
          <div class="modal-actions">
            <button type="button" class="btn btn-primary" @click="closeCreate">Done</button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
type ApiKeyPermission = 'read' | 'read_write'

type ApiKeyRow = {
  id: string
  key: string
  label: string
  permission: ApiKeyPermission
  createdAt: string
  updatedAt: string
}

type CreatedPayload = ApiKeyRow & { secret: string }

const { data, pending, refresh } = useFetch<{ keys: ApiKeyRow[] }>('/api/api-keys')
const keys = computed(() => data.value?.keys ?? [])
const listLoading = computed(() => pending.value)

const revealed = reactive<Record<string, boolean>>({})
const editingId = ref<string | null>(null)
const editingLabel = ref('')
const savingLabel = ref(false)

const createOpen = ref(false)
const creating = ref(false)
const createError = ref('')
const createForm = reactive({
  label: '',
  permission: 'read_write' as ApiKeyPermission,
})
const createdPayload = ref<CreatedPayload | null>(null)

const envSnippet = computed(() => {
  const p = createdPayload.value
  if (!p) return ''
  return `DPANEL_API_KEY=${p.key}\nDPANEL_API_SECRET=${p.secret}`
})

function permissionLabel(p: ApiKeyPermission) {
  return p === 'read_write' ? 'Read & Write' : 'Read Only'
}

function maskKey(key: string) {
  if (key.length <= 10) return '••••••••'
  return `${key.slice(0, 6)}…${key.slice(-4)}`
}

function toggleReveal(id: string) {
  revealed[id] = !revealed[id]
}

function startEdit(row: ApiKeyRow) {
  editingId.value = row.id
  editingLabel.value = row.label
}

function cancelEdit() {
  editingId.value = null
  editingLabel.value = ''
}

async function saveLabel(id: string) {
  const label = editingLabel.value.trim()
  if (!label) return
  savingLabel.value = true
  try {
    await $fetch(`/api/api-keys/${encodeURIComponent(id)}`, {
      method: 'PATCH',
      body: { label },
    })
    cancelEdit()
    await refresh()
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    alert(err.data?.statusMessage || err.statusMessage || 'Failed to update label')
  } finally {
    savingLabel.value = false
  }
}

async function confirmDelete(row: ApiKeyRow) {
  if (!confirm(`Delete API key “${row.label}”? Apps using it will lose access.`)) return
  try {
    await $fetch(`/api/api-keys/${encodeURIComponent(row.id)}`, { method: 'DELETE' })
    await refresh()
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    alert(err.data?.statusMessage || err.statusMessage || 'Failed to delete')
  }
}

function openCreate() {
  createError.value = ''
  createdPayload.value = null
  createForm.label = ''
  createForm.permission = 'read_write'
  createOpen.value = true
}

function closeCreate() {
  createOpen.value = false
  createdPayload.value = null
  createError.value = ''
  void refresh()
}

async function submitCreate() {
  creating.value = true
  createError.value = ''
  try {
    createdPayload.value = await $fetch<CreatedPayload>('/api/api-keys', {
      method: 'POST',
      body: {
        label: createForm.label,
        permission: createForm.permission,
      },
    })
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    createError.value = err.data?.statusMessage || err.statusMessage || 'Failed to create'
  } finally {
    creating.value = false
  }
}

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text)
  } catch {
    alert('Copy failed — select and copy manually')
  }
}
</script>

<style scoped>
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.75rem;
  flex-wrap: wrap;
  gap: 0.75rem;
}
.page-desc {
  color: var(--muted);
  margin: 0 0 1.25rem;
  max-width: 52rem;
  line-height: 1.45;
  font-size: 0.92rem;
}
.page-desc code {
  font-size: 0.85em;
}
.muted {
  color: var(--muted);
}
.table-wrap {
  overflow-x: auto;
}
.col-actions {
  text-align: right;
  white-space: nowrap;
}
.key-cell {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}
.mono {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 0.82rem;
}
.mono.block {
  display: block;
  word-break: break-all;
  padding: 0.5rem 0.65rem;
  background: var(--surface-elevated);
  border: 1px solid var(--border);
  border-radius: 8px;
  flex: 1;
}
.secret-placeholder {
  color: var(--muted);
  letter-spacing: 0.08em;
  font-size: 0.85rem;
}
.icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--surface-elevated);
  color: var(--text);
  cursor: pointer;
}
.icon-btn:hover:not(:disabled) {
  border-color: var(--accent);
  color: var(--accent);
}
.icon-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.icon-btn-danger:hover:not(:disabled) {
  border-color: #c44;
  color: #c44;
}
.label-edit {
  min-width: 10rem;
}
.input-inline {
  width: 100%;
  min-width: 8rem;
}
.badge {
  display: inline-block;
  padding: 0.15rem 0.5rem;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 600;
}
.badge-read {
  background: var(--accent-muted, #e8eef8);
  color: var(--accent, #345);
}
.badge-write {
  background: #e8f5e9;
  color: #2e7d32;
}
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 80;
  padding: 1rem;
}
.modal {
  width: min(520px, 100%);
  max-height: 90vh;
  overflow: auto;
}
.modal h2 {
  margin: 0 0 1rem;
  font-size: 1.15rem;
}
.field {
  margin-bottom: 0.9rem;
}
.radio-row {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  margin: 0.4rem 0;
  font-size: 0.9rem;
  cursor: pointer;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}
.warn {
  color: #b45309;
  background: #fff7ed;
  border: 1px solid #fdba74;
  border-radius: 8px;
  padding: 0.65rem 0.75rem;
  font-size: 0.88rem;
  margin: 0 0 1rem;
}
.copy-row {
  display: flex;
  gap: 0.5rem;
  align-items: flex-start;
}
.env-snippet {
  margin: 0;
  flex: 1;
  padding: 0.5rem 0.65rem;
  background: var(--surface-elevated);
  border: 1px solid var(--border);
  border-radius: 8px;
  font-size: 0.8rem;
  white-space: pre-wrap;
  word-break: break-all;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}
.alert-error {
  color: #b91c1c;
  font-size: 0.88rem;
}
</style>
