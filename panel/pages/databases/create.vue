<template>
  <div>
    <PageLoader v-if="pageLoading" label="Loading…" />
    <template v-else>
    <h1>Create database</h1>
    <div v-if="message" :class="['alert', ok ? 'alert-success' : 'alert-error']">{{ message }}</div>
    <form class="card form" @submit.prevent="submit">
      <div class="field">
        <label class="label">Database name</label>
        <input v-model="name" class="input" pattern="[a-zA-Z0-9_]+" required placeholder="myapp_db" />
      </div>
      <div class="field">
        <label class="label">User (optional, defaults to database name)</label>
        <input v-model="user" class="input" placeholder="myapp_user" />
      </div>
      <div class="field">
        <label class="label">Password (optional, auto-generated if empty)</label>
        <input v-model="password" class="input" type="password" />
      </div>
      <button class="btn btn-primary" type="submit" :disabled="submitting">
        {{ submitting ? 'Creating…' : 'Create database' }}
      </button>
    </form>
    <div v-if="created" class="card creds">
      <h2>Connection details</h2>
      <p><strong>Database:</strong> {{ created.name }}</p>
      <p><strong>User:</strong> {{ created.user }}</p>
      <p><strong>Password:</strong> <code>{{ created.password }}</code></p>
      <p class="muted">Save these credentials — the password will not be shown again after you leave this page.</p>
    </div>
    </template>
  </div>
</template>

<script setup lang="ts">
const { loading: pageLoading } = usePageInit()
const name = ref('')
const user = ref('')
const password = ref('')
const submitting = ref(false)
const message = ref('')
const ok = ref(false)
const created = ref<{ name: string; user: string; password: string } | null>(null)

async function submit() {
  message.value = ''
  submitting.value = true
  created.value = null
  try {
    const res = await $fetch<{ name: string; user: string; password: string }>('/api/databases', {
      method: 'POST',
      body: {
        name: name.value.trim(),
        user: user.value.trim() || undefined,
        password: password.value || undefined
      }
    })
    ok.value = true
    created.value = res
    message.value = 'Database created successfully.'
  } catch (e: unknown) {
    ok.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    message.value = err.data?.statusMessage || err.statusMessage || 'Error'
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
.form { max-width: 480px; margin: 1rem 0; }
.creds { max-width: 480px; margin-top: 1rem; }
.creds h2 { font-size: 1rem; margin-bottom: 0.75rem; }
.muted { color: var(--muted); font-size: 0.85rem; margin-top: 0.5rem; }
</style>
