<template>
  <div>
    <div class="header">
      <h1>Websites</h1>
      <NuxtLink to="/websites/create" class="btn btn-primary">+ Create website</NuxtLink>
    </div>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <PageLoader v-if="pending" label="Loading websites…" />
    <div v-else-if="!sites.length" class="card muted">No websites yet. Create your first site.</div>
    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Domain</th>
            <th>Runtime</th>
            <th>Status</th>
            <th>GitHub</th>
            <th class="created-col">Created</th>
            <th class="col-actions">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in sites" :key="s.domain" :class="{ 'row-pending': !!s.pendingDeleteAt }">
            <td><strong>{{ s.domain }}</strong></td>
            <td>
              <span :class="s.runtime === 'node' ? 'badge badge-node' : 'badge badge-php'">
                {{ runtimeLabel(s.runtime) }}
              </span>
            </td>
            <td>
              <span v-if="s.pendingDeleteAt" class="badge badge-pending" :title="s.pendingDeleteExpiresAt || ''">
                Pending delete
              </span>
              <span v-else class="status-active">Active</span>
            </td>
            <td class="github-cell">{{ s.githubUrl || '—' }}</td>
            <td class="created-col">{{ formatDate(s.createdAt) }}</td>
            <td class="col-actions">
              <div class="action-row">
                <button
                  v-if="s.pendingDeleteAt"
                  type="button"
                  class="btn btn-ghost btn-sm"
                  :disabled="busy === s.domain"
                  @click="restoreSite(s.domain)"
                >
                  {{ busy === s.domain ? 'Restoring…' : 'Restore' }}
                </button>
                <NuxtLink
                  :to="`/websites/${encodeURIComponent(s.domain)}/files`"
                  class="btn btn-ghost btn-sm manager-link"
                  title="File manager"
                >
                  <AppIcon name="folder" :size="14" />
                  <span>Files</span>
                </NuxtLink>
                <NuxtLink
                  :to="`/websites/${encodeURIComponent(s.domain)}`"
                  class="btn btn-ghost btn-sm manager-link"
                  title="Manager"
                >
                  <AppIcon name="settings" :size="14" />
                  <span>Manager</span>
                </NuxtLink>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = {
  domain: string
  runtime: string
  githubUrl?: string
  createdAt?: string
  pendingDeleteAt?: string | null
  pendingDeleteExpiresAt?: string | null
}

const { data, pending, refresh } = useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])
const busy = ref('')
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

function formatDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US')
}

async function restoreSite(domain: string) {
  busy.value = domain
  clearAlert()
  try {
    await $fetch(`/api/websites/${encodeURIComponent(domain)}/restore`, { method: 'POST' })
    showAlert(`Restored ${domain}`, true)
    await refresh()
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Restore failed', false)
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
.action-row {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  justify-content: flex-end;
}
.manager-link {
  text-decoration: none;
}
.github-cell {
  max-width: min(280px, 28vw);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--text-sm);
}
.created-col {
  font-size: var(--text-xs);
  color: var(--muted);
  white-space: nowrap;
}
.row-pending td {
  opacity: 0.92;
}
</style>
