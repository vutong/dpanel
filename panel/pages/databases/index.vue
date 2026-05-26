<template>
  <div>
    <div class="header">
      <h1>Databases</h1>
      <NuxtLink to="/databases/create" class="btn btn-primary">+ Create database</NuxtLink>
    </div>

    <PageLoader v-if="pending" label="Loading databases…" />
    <div v-else-if="!databases.length" class="card muted">
      No user databases yet.
      <NuxtLink to="/databases/create">Create a database</NuxtLink>
    </div>
    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Database</th>
            <th>User</th>
            <th class="col-actions">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="db in databases" :key="db.name">
            <td><strong>{{ db.name }}</strong></td>
            <td><code>{{ db.user }}</code></td>
            <td class="col-actions">
              <div class="action-btns">
                <IconButton
                  icon="lock"
                  title="Reset password"
                  :disabled="!!busy"
                  :busy="busy === db.name"
                  @click="openModify(db)"
                />
                <IconButton
                  icon="trash"
                  title="Delete database"
                  variant="danger"
                  :disabled="!!busy"
                  :busy="busy === db.name"
                  @click="openDelete(db)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" />

    <div v-if="modifyTarget" class="modal-backdrop" @click.self="closeModify">
      <div class="modal card" role="dialog" aria-labelledby="modify-title">
        <h2 id="modify-title">Reset password</h2>
        <p class="muted">
          Database <strong>{{ modifyTarget.name }}</strong> — user <code>{{ modifyTarget.user }}</code>
        </p>
        <div v-if="modifyPhase === 'confirm'" class="field">
          <label class="label">New password (optional)</label>
          <input
            v-model="modifyPassword"
            class="input"
            type="password"
            placeholder="Leave empty to auto-generate"
            autocomplete="new-password"
          />
        </div>
        <div v-else-if="modifyResult" class="creds">
          <p><strong>User:</strong> {{ modifyResult.user }}</p>
          <p><strong>Password:</strong> <code>{{ modifyResult.password }}</code></p>
          <p class="hint">Save this password — it will not be shown again after you close.</p>
        </div>
        <p v-else class="alert alert-info">Resetting password…</p>
        <div class="modal-actions">
          <button
            v-if="modifyPhase === 'confirm'"
            type="button"
            class="btn btn-ghost"
            @click="closeModify"
          >
            Cancel
          </button>
          <button v-else type="button" class="btn btn-primary" @click="closeModify">Close</button>
          <button
            v-if="modifyPhase === 'confirm'"
            type="button"
            class="btn btn-primary"
            :disabled="!!busy"
            @click="confirmModify"
          >
            Reset password
          </button>
        </div>
      </div>
    </div>

    <div v-if="deleteTarget" class="modal-backdrop" @click.self="closeDelete">
      <div class="modal card" role="dialog" aria-labelledby="delete-db-title">
        <h2 id="delete-db-title">Delete database</h2>
        <p class="muted">
          Remove <strong>{{ deleteTarget.name }}</strong> and MariaDB user <code>{{ deleteTarget.user }}</code>.
        </p>
        <p class="hint">This permanently deletes the database and user. It cannot be undone.</p>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" :disabled="!!busy" @click="closeDelete">
            Cancel
          </button>
          <button
            type="button"
            class="btn btn-danger"
            :disabled="!!busy"
            @click="confirmDelete"
          >
            {{ busy === deleteTarget.name ? 'Deleting…' : 'Delete database' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
type DatabaseRow = { name: string; user: string; createdAt?: string | null }

const { data, pending, refresh } = useFetch<{ databases: DatabaseRow[] }>('/api/databases')
const databases = computed(() => data.value?.databases ?? [])

const modifyTarget = ref<DatabaseRow | null>(null)
const modifyPhase = ref<'confirm' | 'done'>('confirm')
const modifyPassword = ref('')
const modifyResult = ref<{ user: string; password: string } | null>(null)
const deleteTarget = ref<DatabaseRow | null>(null)
const busy = ref('')
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

function openModify(db: DatabaseRow) {
  modifyTarget.value = db
  modifyPhase.value = 'confirm'
  modifyPassword.value = ''
  modifyResult.value = null
  clearAlert()
}

function closeModify() {
  modifyTarget.value = null
  modifyPhase.value = 'confirm'
  modifyResult.value = null
}

async function confirmModify() {
  const db = modifyTarget.value
  if (!db || modifyPhase.value !== 'confirm') return

  busy.value = db.name
  clearAlert()
  try {
    const res = await $fetch<{ user: string; password: string }>(
      `/api/databases/${encodeURIComponent(db.name)}/modify`,
      {
        method: 'POST',
        body: {
          user: db.user,
          password: modifyPassword.value.trim() || undefined
        }
      }
    )
    modifyPhase.value = 'done'
    modifyResult.value = { user: res.user, password: res.password }
    clearAlert()
    await refresh()
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Failed to reset password', false)
  } finally {
    busy.value = ''
  }
}

function openDelete(db: DatabaseRow) {
  deleteTarget.value = db
  clearAlert()
}

function closeDelete() {
  if (busy.value) return
  deleteTarget.value = null
}

async function confirmDelete() {
  const db = deleteTarget.value
  if (!db) return

  busy.value = db.name
  clearAlert()
  try {
    const res = await $fetch<{ ok: boolean; name: string; droppedUser?: string | null }>(
      `/api/databases/${encodeURIComponent(db.name)}`,
      { method: 'DELETE', query: { user: db.user } }
    )
    showAlert(
      res.droppedUser
        ? `Deleted database ${res.name} and user ${res.droppedUser}`
        : `Deleted database ${res.name}`,
      true
    )
    deleteTarget.value = null
    await refresh()
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Delete failed', false)
  } finally {
    busy.value = ''
  }
}
</script>

<style scoped>
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.25rem;
  flex-wrap: wrap;
  gap: 0.75rem;
}
.muted { color: var(--muted); }
.muted a { margin-left: 0.35rem; }
.table-wrap { overflow-x: auto; }
.col-actions {
  text-align: right;
  white-space: nowrap;
  overflow: visible;
}
.action-btns {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  justify-content: flex-end;
  overflow: visible;
}
code { font-size: 0.88rem; color: var(--muted); }
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
  padding: 1rem;
}
.modal {
  width: 100%;
  max-width: 440px;
}
.modal h2 {
  margin-bottom: 0.75rem;
  font-size: 1.15rem;
}
.hint {
  font-size: 0.8rem;
  color: var(--muted);
  margin: 0.75rem 0 1rem;
  line-height: 1.45;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}
.creds p { margin-bottom: 0.5rem; }
.creds code {
  word-break: break-all;
  color: var(--text);
}
</style>
