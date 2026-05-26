<template>
  <div>
    <h1>Delete database</h1>
    <p class="muted">Permanently remove a database and optionally its MariaDB user. This cannot be undone.</p>

    <div v-if="message" :class="['alert', ok ? 'alert-success' : 'alert-error']">{{ message }}</div>

    <div v-if="pending" class="muted">Loading databases...</div>
    <div v-else-if="!databases.length" class="card muted">
      No user databases to delete.
      <NuxtLink to="/databases/create">Create a database</NuxtLink>
    </div>
    <form v-else class="card form" @submit.prevent="submit">
      <div class="field">
        <label class="label">Database</label>
        <select v-model="selected" class="select" required>
          <option value="" disabled>Select database</option>
          <option v-for="db in databases" :key="db" :value="db">{{ db }}</option>
        </select>
      </div>
      <div class="field">
        <label class="label">MariaDB user to remove</label>
        <input
          v-model="dbUser"
          class="input"
          pattern="[a-zA-Z0-9_]+"
          placeholder="Same as database name if created via panel"
        />
        <p class="hint">Leave as database name to drop the matching user (typical for panel-created DBs).</p>
      </div>
      <label class="checkbox-label">
        <input v-model="dropUser" type="checkbox" />
        Drop MariaDB user as well
      </label>
      <button class="btn btn-danger" type="submit" :disabled="loading || !selected">
        {{ loading ? 'Deleting…' : 'Delete database' }}
      </button>
    </form>
  </div>
</template>

<script setup lang="ts">
const { data, pending, refresh } = await useFetch<{ databases: string[] }>('/api/databases')
const databases = computed(() => data.value?.databases ?? [])

const selected = ref('')
const dbUser = ref('')
const dropUser = ref(true)
const loading = ref(false)
const message = ref('')
const ok = ref(false)

watch(selected, (name) => {
  if (name && !dbUser.value) dbUser.value = name
})

async function submit() {
  const name = selected.value.trim()
  if (!name) return
  if (!confirm(`Delete database "${name}"? This cannot be undone.`)) return

  message.value = ''
  loading.value = true
  try {
    const query: Record<string, string> = {}
    if (!dropUser.value) query.keepUser = '1'
    if (dbUser.value.trim() && dbUser.value.trim() !== name) {
      query.user = dbUser.value.trim()
    }
    const res = await $fetch<{ ok: boolean; name: string; droppedUser?: string | null }>(
      `/api/databases/${encodeURIComponent(name)}`,
      { method: 'DELETE', query }
    )
    ok.value = true
    message.value = res.droppedUser
      ? `Deleted database ${res.name} and user ${res.droppedUser}`
      : `Deleted database ${res.name}`
    selected.value = ''
    dbUser.value = ''
    await refresh()
  } catch (e: unknown) {
    ok.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    message.value = err.data?.statusMessage || err.statusMessage || 'Delete failed'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.form { max-width: 480px; margin: 1rem 0; }
.hint { font-size: 0.8rem; color: var(--muted); margin-top: 0.35rem; }
.checkbox-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 1rem 0;
  font-size: 0.9rem;
  cursor: pointer;
}
.muted { color: var(--muted); margin-bottom: 1rem; }
.muted a { margin-left: 0.35rem; }
</style>
