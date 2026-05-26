<template>
  <div>
    <div class="header">
      <h1>Websites</h1>
      <NuxtLink to="/websites/create" class="btn btn-primary">+ Create website</NuxtLink>
    </div>

    <PageLoader v-if="pending" label="Loading websites…" />
    <div v-else-if="!sites.length" class="card muted">No websites yet. Create your first site.</div>
    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Domain</th>
            <th>Runtime</th>
            <th>GitHub</th>
            <th>Created</th>
            <th class="col-actions">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in sites" :key="s.domain">
            <td><strong>{{ s.domain }}</strong></td>
            <td>
              <span :class="s.runtime === 'node' ? 'badge badge-node' : 'badge badge-php'">
                {{ s.runtime }}
              </span>
            </td>
            <td class="github-cell">{{ s.githubUrl || '—' }}</td>
            <td>{{ formatDate(s.createdAt) }}</td>
            <td class="col-actions">
              <div class="action-btns">
                <IconButton
                  v-if="s.githubUrl"
                  icon="git-pull"
                  title="Update from Git"
                  :disabled="!!busy"
                  :busy="busy === s.domain"
                  @click="openUpdate(s)"
                />
                <IconButton
                  v-if="s.runtime === 'node'"
                  icon="wrench"
                  title="Rebuild (npm build)"
                  :disabled="!!busy"
                  :busy="busy === s.domain"
                  @click="runRebuild(s)"
                />
                <IconButton
                  icon="trash"
                  title="Delete website"
                  variant="danger"
                  :disabled="!!busy"
                  :busy="busy === s.domain"
                  @click="openDelete(s)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <p v-if="msg" class="alert" :class="ok ? 'alert-success' : 'alert-error'">{{ msg }}</p>

    <div v-if="updateTarget" class="modal-backdrop" @click.self="closeUpdate">
      <div class="modal card" role="dialog" aria-labelledby="update-title">
        <h2 id="update-title">Update from Git</h2>
        <p class="muted">
          Pull latest code for <strong>{{ updateTarget.domain }}</strong>
          <span v-if="updateTarget.githubUrl" class="repo-url">{{ updateTarget.githubUrl }}</span>
        </p>
        <div class="field">
          <label class="label">GitHub token (PAT)</label>
          <input
            v-model="updateToken"
            class="input"
            type="password"
            placeholder="Required for private repos; leave empty if public"
            autocomplete="off"
          />
          <p class="hint">
            Token is not stored. If pull fails with 401/403, your PAT may be <strong>expired</strong> — create a new one
            (<code>ghp_...</code> with <code>repo</code> scope).
          </p>
        </div>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" :disabled="!!busy" @click="closeUpdate">
            Cancel
          </button>
          <button type="button" class="btn btn-primary" :disabled="!!busy" @click="confirmUpdate">
            {{ busy === updateTarget.domain ? 'Pulling…' : 'Pull from Git' }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="deleteTarget" class="modal-backdrop" @click.self="closeDelete">
      <div class="modal card" role="dialog" aria-labelledby="delete-title">
        <h2 id="delete-title">Delete website</h2>
        <p class="muted">
          Remove <strong>{{ deleteTarget.domain }}</strong> from the panel and stack.
        </p>
        <ul class="delete-list">
          <li>Panel registry (<code>sites.json</code>)</li>
          <li>Nginx vhost (<code>conf.d/</code> and <code>conf.d/disabled/</code>)</li>
          <li><code>apps/{{ deleteTarget.domain }}/</code> (application files)</li>
          <li v-if="deleteTarget.runtime === 'node'">
            Docker <code>nuxt-{{ slug(deleteTarget.domain) }}</code> and
            <code>compose.d/nuxt-{{ slug(deleteTarget.domain) }}.yml</code>
          </li>
        </ul>
        <p class="hint">This permanently removes all related files and cannot be undone.</p>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" :disabled="!!busy" @click="closeDelete">
            Cancel
          </button>
          <button type="button" class="btn btn-danger" :disabled="!!busy" @click="confirmDelete">
            {{ busy === deleteTarget.domain ? 'Deleting…' : 'Delete website' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
type DeleteResult = { ok: boolean; domain?: string; purged?: boolean; removed?: string[] }

const { data, pending, refresh } = useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])

const deleteTarget = ref<Site | null>(null)
const updateTarget = ref<Site | null>(null)
const updateToken = ref('')
const busy = ref('')
const msg = ref('')
const ok = ref(false)

function slug(domain: string) {
  return domain.replace(/\./g, '-').replace(/[^a-zA-Z0-9-]/g, '')
}

function openUpdate(site: Site) {
  updateTarget.value = site
  updateToken.value = ''
  msg.value = ''
}

function closeUpdate() {
  if (busy.value) return
  updateTarget.value = null
}

async function confirmUpdate() {
  const site = updateTarget.value
  if (!site) return

  busy.value = site.domain
  msg.value = ''
  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.domain)}/update`, {
      method: 'POST',
      body: { githubToken: updateToken.value.trim() || undefined }
    })
    ok.value = true
    msg.value = `Updated ${site.domain} from Git`
    updateTarget.value = null
    await refresh()
  } catch (e: unknown) {
    ok.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    msg.value = err.data?.statusMessage || err.statusMessage || 'Git update failed'
  } finally {
    busy.value = ''
  }
}

async function runRebuild(site: Site) {
  if (site.runtime !== 'node') return
  busy.value = site.domain
  msg.value = ''
  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.domain)}/rebuild`, { method: 'POST' })
    ok.value = true
    msg.value = `Rebuilt ${site.domain} (npm build + container restart)`
  } catch (e: unknown) {
    ok.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    msg.value = err.data?.statusMessage || err.statusMessage || 'Rebuild failed'
  } finally {
    busy.value = ''
  }
}

function openDelete(site: Site) {
  deleteTarget.value = site
}

function closeDelete() {
  if (busy.value) return
  deleteTarget.value = null
}

async function confirmDelete() {
  const site = deleteTarget.value
  if (!site) return

  busy.value = site.domain
  msg.value = ''
  try {
    const result = await $fetch<DeleteResult>(
      `/api/websites/${encodeURIComponent(site.domain)}`,
      { method: 'DELETE' }
    )
    ok.value = true
    const n = result.removed?.length ?? 0
    msg.value =
      n > 0
        ? `Deleted ${site.domain} (${n} item${n === 1 ? '' : 's'} removed)`
        : `Deleted ${site.domain}`
    deleteTarget.value = null
    await refresh()
  } catch (e: unknown) {
    ok.value = false
    const err = e as {
      data?: { statusMessage?: string; message?: string }
      statusMessage?: string
      message?: string
      statusCode?: number
    }
    const raw =
      err.data?.statusMessage ||
      err.data?.message ||
      err.statusMessage ||
      err.message ||
      ''
    if (err.statusCode === 502 || /bad gateway/i.test(raw)) {
      msg.value =
        'Gateway error while waiting — the site may still be deleting. Refresh the list in a few seconds.'
      await refresh()
    } else {
      msg.value = raw || 'Delete failed'
    }
  } finally {
    busy.value = ''
  }
}

function formatDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US')
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
.table-wrap {
  overflow-x: auto;
}
.col-actions {
  text-align: right;
  white-space: nowrap;
}
.action-btns {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  justify-content: flex-end;
}
.github-cell {
  max-width: min(280px, 28vw);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.85rem;
}
.repo-url {
  display: block;
  font-size: 0.8rem;
  margin-top: 0.35rem;
  word-break: break-all;
}
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
  max-width: 480px;
}
.modal h2 {
  margin-bottom: 0.75rem;
  font-size: 1.15rem;
}
.delete-list {
  margin: 1rem 0;
  padding-left: 1.25rem;
  color: var(--text);
  font-size: 0.9rem;
}
.delete-list li { margin-bottom: 0.35rem; }
.delete-list code {
  font-size: 0.8rem;
  color: var(--muted);
}
.hint {
  font-size: 0.8rem;
  color: var(--muted);
  margin-bottom: 1rem;
  line-height: 1.45;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}
</style>
