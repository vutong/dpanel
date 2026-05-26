<template>
  <div>
    <div class="header">
      <h1>Websites</h1>
      <NuxtLink to="/websites/create" class="btn btn-primary">+ Create website</NuxtLink>
    </div>

    <div v-if="pending" class="muted">Loading...</div>
    <div v-else-if="!sites.length" class="card muted">No websites yet. Create your first site.</div>
    <div v-else class="card">
      <table class="table">
        <thead>
          <tr>
            <th>Domain</th>
            <th>Runtime</th>
            <th>GitHub</th>
            <th>Created</th>
            <th style="text-align: right">Actions</th>
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
            <td style="text-align: right">
              <button
                type="button"
                class="btn btn-danger"
                :disabled="!!removing"
                @click="openDelete(s)"
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <p v-if="msg" class="alert" :class="ok ? 'alert-success' : 'alert-error'">{{ msg }}</p>

    <div v-if="deleteTarget" class="modal-backdrop" @click.self="closeDelete">
      <div class="modal card" role="dialog" aria-labelledby="delete-title">
        <h2 id="delete-title">Delete website</h2>
        <p class="muted">
          Remove <strong>{{ deleteTarget.domain }}</strong> from the panel and stack.
        </p>
        <ul class="delete-list">
          <li>Panel registry (<code>sites.json</code>)</li>
          <li>Nginx vhost (<code>infra/nginx/conf.d/{{ deleteTarget.domain }}.conf</code>)</li>
          <li v-if="deleteTarget.runtime === 'node'">
            Docker service <code>nuxt-{{ slug(deleteTarget.domain) }}</code> and
            <code>compose.d/nuxt-{{ slug(deleteTarget.domain) }}.yml</code>
          </li>
          <li v-else>PHP site nginx config (app files served from <code>apps/{{ deleteTarget.domain }}/</code>)</li>
        </ul>
        <label class="purge-label">
          <input v-model="purgeFiles" type="checkbox" />
          Also delete <code>apps/{{ deleteTarget.domain }}/</code> (all application files and uploads inside the project)
        </label>
        <p v-if="!purgeFiles" class="hint">
          If unchecked, code remains on disk — you can redeploy the same domain later.
        </p>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" :disabled="!!removing" @click="closeDelete">
            Cancel
          </button>
          <button
            type="button"
            class="btn btn-danger"
            :disabled="!!removing"
            @click="confirmDelete"
          >
            {{ removing ? 'Deleting…' : 'Delete website' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
type DeleteResult = { ok: boolean; domain?: string; purged?: boolean; removed?: string[] }

const { data, pending, refresh } = await useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])

const deleteTarget = ref<Site | null>(null)
const purgeFiles = ref(false)
const removing = ref('')
const msg = ref('')
const ok = ref(false)

function slug(domain: string) {
  return domain.replace(/\./g, '-').replace(/[^a-zA-Z0-9-]/g, '')
}

function openDelete(site: Site) {
  deleteTarget.value = site
  purgeFiles.value = false
}

function closeDelete() {
  if (removing.value) return
  deleteTarget.value = null
}

async function confirmDelete() {
  const site = deleteTarget.value
  if (!site) return

  removing.value = site.domain
  msg.value = ''
  try {
    const result = await $fetch<DeleteResult>(
      `/api/websites/${encodeURIComponent(site.domain)}`,
      {
        method: 'DELETE',
        query: purgeFiles.value ? { purge: '1' } : {}
      }
    )
    ok.value = true
    const n = result.removed?.length ?? 0
    msg.value =
      n > 0
        ? `Deleted ${site.domain} (${n} stack item${n === 1 ? '' : 's'} removed${result.purged ? ', files purged' : ''})`
        : `Deleted ${site.domain}`
    deleteTarget.value = null
    await refresh()
  } catch (e: unknown) {
    ok.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    msg.value = err.data?.statusMessage || err.statusMessage || 'Delete failed'
  } finally {
    removing.value = ''
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
.github-cell {
  max-width: 220px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.85rem;
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
.purge-label {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  font-size: 0.9rem;
  cursor: pointer;
  margin-bottom: 0.5rem;
}
.hint {
  font-size: 0.8rem;
  color: var(--muted);
  margin-bottom: 1rem;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}
</style>
