<template>
  <div>
    <div class="header">
      <h1>Databases</h1>
      <div class="actions">
        <NuxtLink to="/databases/phpmyadmin" class="btn btn-ghost">phpMyAdmin</NuxtLink>
        <NuxtLink to="/databases/create" class="btn btn-primary">+ Create database</NuxtLink>
      </div>
    </div>
    <div v-if="pending" class="muted">Loading...</div>
    <div v-else-if="!databases.length" class="card muted">No user databases yet.</div>
    <div v-else class="card">
      <table class="table">
        <thead>
          <tr>
            <th>Name</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="db in databases" :key="db">
            <td><code>{{ db }}</code></td>
            <td style="text-align:right">
              <button
                class="btn btn-danger"
                type="button"
                :disabled="deleting === db"
                @click="remove(db)"
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="deleteMsg" class="alert" :class="deleteOk ? 'alert-success' : 'alert-error'">{{ deleteMsg }}</p>
  </div>
</template>

<script setup lang="ts">
const { data, pending, refresh } = await useFetch<{ databases: string[] }>('/api/databases')
const databases = computed(() => data.value?.databases ?? [])
const deleting = ref('')
const deleteMsg = ref('')
const deleteOk = ref(false)

async function remove(name: string) {
  if (!confirm(`Delete database "${name}"? This cannot be undone.`)) return
  deleting.value = name
  deleteMsg.value = ''
  try {
    await $fetch(`/api/databases/${encodeURIComponent(name)}`, { method: 'DELETE' })
    deleteOk.value = true
    deleteMsg.value = `Deleted ${name}`
    await refresh()
  } catch (e: unknown) {
    deleteOk.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    deleteMsg.value = err.data?.statusMessage || err.statusMessage || 'Delete failed'
  } finally {
    deleting.value = ''
  }
}
</script>

<style scoped>
.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.25rem; flex-wrap: wrap; gap: 0.75rem; }
.actions { display: flex; gap: 0.5rem; }
code { font-size: 0.9rem; }
</style>
