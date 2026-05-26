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
            <th></th>
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
            <td>{{ s.githubUrl || '—' }}</td>
            <td>{{ formatDate(s.createdAt) }}</td>
            <td>
              <button
                type="button"
                class="btn btn-danger btn-sm"
                :disabled="removing === s.domain"
                @click="removeSite(s.domain)"
              >
                {{ removing === s.domain ? 'Removing…' : 'Remove' }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="msg" class="alert" :class="ok ? 'alert-success' : 'alert-error'">{{ msg }}</p>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
const { data, pending, refresh } = await useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])
const removing = ref('')
const msg = ref('')
const ok = ref(false)

async function removeSite(domain: string) {
  if (!confirm(`Remove ${domain}? (nginx, Docker service, and panel entry)`)) return
  const deleteFiles = confirm(
    `Also delete apps/${domain}/ entirely? (includes uploads managed by the app, e.g. wp-content/uploads)`
  )
  removing.value = domain
  msg.value = ''
  try {
    await $fetch(`/api/websites/${encodeURIComponent(domain)}`, {
      method: 'DELETE',
      query: deleteFiles ? { purge: '1' } : {}
    })
    ok.value = true
    msg.value = `Removed ${domain}`
    await refresh()
  } catch (e: unknown) {
    ok.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    msg.value = err.data?.statusMessage || err.statusMessage || 'Remove failed'
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
.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem; }
.muted { color: var(--muted); }
.btn-sm { padding: 0.25rem 0.6rem; font-size: 0.85rem; }
.btn-danger { background: #b91c1c; color: #fff; border: none; cursor: pointer; }
.btn-danger:disabled { opacity: 0.6; cursor: not-allowed; }
.alert { margin-top: 1rem; padding: 0.75rem 1rem; border-radius: 6px; }
.alert-success { background: #14532d33; color: #86efac; }
.alert-error { background: #7f1d1d33; color: #fca5a5; }
</style>
