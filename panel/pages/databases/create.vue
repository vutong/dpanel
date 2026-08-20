<template>
  <div>
    <PageLoader v-if="pageLoading" label="Loading…" />
    <template v-else>
    <h1>Create database</h1>
    <div v-if="message" :class="['alert', ok ? 'alert-success' : 'alert-error']">{{ message }}</div>
    <form class="card form" @submit.prevent="submit">
      <div class="field">
        <label class="label">Website</label>
        <select v-model="siteDomain" class="select" required>
          <option disabled value="">Select a website…</option>
          <option v-for="s in sites" :key="s.domain" :value="s.domain">
            {{ s.domain }} ({{ runtimeLabel(s.runtime) }})
          </option>
        </select>
        <p class="hint">
          MariaDB works with <strong>Node SSR</strong> and <strong>PHP</strong> sites.
          <template v-if="!sites.length">
            No websites yet —
            <NuxtLink to="/websites/create">create a website</NuxtLink>
            first.
          </template>
        </p>
      </div>
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
        <div class="input-wrap">
          <input
            v-model="password"
            class="input input-with-actions"
            :type="showPassword ? 'text' : 'password'"
            autocomplete="new-password"
          />
          <div class="input-actions">
            <button
              type="button"
              class="input-action"
              :title="showPassword ? 'Hide password' : 'Show password'"
              :aria-label="showPassword ? 'Hide password' : 'Show password'"
              @click="showPassword = !showPassword"
            >
              <AppIcon :name="showPassword ? 'eye-off' : 'eye'" :size="16" />
            </button>
            <button
              type="button"
              class="input-action"
              title="Generate password"
              aria-label="Generate password"
              @click="generatePassword"
            >
              <AppIcon name="sparkles" :size="16" />
            </button>
          </div>
        </div>
      </div>
      <button class="btn btn-primary" type="submit" :disabled="submitting || !sites.length">
        {{ submitting ? 'Creating…' : 'Create database' }}
      </button>
    </form>
    <div v-if="created" class="card creds">
      <h2>Connection details</h2>
      <p><strong>Website:</strong> {{ created.siteDomain }}</p>
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
const route = useRoute()

const { data: sitesData } = await useFetch<{ sites: { domain: string; runtime: string }[] }>(
  '/api/websites'
)
const sites = computed(() => sitesData.value?.sites ?? [])

const preset = String(route.query.site || '').trim().toLowerCase()
const siteDomain = ref(
  preset && sites.value.some((s) => s.domain === preset) ? preset : ''
)
const name = ref('')
const user = ref('')
const password = ref('')
const showPassword = ref(false)
const submitting = ref(false)
const message = ref('')
const ok = ref(false)
const created = ref<{
  name: string
  user: string
  password: string
  siteDomain?: string
} | null>(null)

function generatePassword() {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  const length = 16
  const maxUnbiased = 256 - (256 % chars.length)
  let out = ''
  while (out.length < length) {
    const bytes = new Uint8Array(length - out.length)
    crypto.getRandomValues(bytes)
    for (const b of bytes) {
      if (b >= maxUnbiased) continue
      out += chars[b % chars.length]
      if (out.length === length) break
    }
  }
  password.value = out
  showPassword.value = true
}

async function submit() {
  message.value = ''
  submitting.value = true
  created.value = null
  try {
    const res = await $fetch<{
      name: string
      user: string
      password: string
      siteDomain?: string
    }>('/api/databases', {
      method: 'POST',
      body: {
        name: name.value.trim(),
        siteDomain: siteDomain.value.trim(),
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
.hint {
  font-size: 0.8rem;
  color: var(--muted);
  margin-top: 0.4rem;
  line-height: 1.4;
}
.hint a { color: var(--accent); }
.input-wrap {
  position: relative;
}
.input-with-actions {
  padding-right: 4.75rem;
}
.input-actions {
  position: absolute;
  right: 0.35rem;
  top: 50%;
  transform: translateY(-50%);
  display: flex;
  align-items: center;
  gap: 0.1rem;
}
.input-action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.85rem;
  height: 1.85rem;
  padding: 0;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--muted);
  cursor: pointer;
}
.input-action:hover {
  color: var(--accent);
  background: var(--accent-muted);
}
</style>
