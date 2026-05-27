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
            <th class="created-col">Created</th>
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
            <td class="created-col">{{ formatDate(s.createdAt) }}</td>
            <td class="col-actions">
              <NuxtLink
                :to="`/websites/${encodeURIComponent(s.domain)}`"
                class="manager-link"
                title="Manager"
              >
                <AppIcon name="settings" :size="18" />
                <span>Manager</span>
              </NuxtLink>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }

const { data, pending } = useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])

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
.manager-link {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.4rem 0.75rem;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface-elevated);
  color: var(--text);
  font-size: 0.85rem;
  font-weight: 500;
  text-decoration: none;
  transition:
    border-color 0.15s,
    color 0.15s,
    background 0.15s;
}
.manager-link:hover {
  border-color: var(--accent);
  color: var(--accent);
  background: var(--accent-muted);
  text-decoration: none;
}
.github-cell {
  max-width: min(280px, 28vw);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.85rem;
}
.created-col {
  font-size: 0.82rem;
  color: var(--muted);
  white-space: nowrap;
}
</style>
