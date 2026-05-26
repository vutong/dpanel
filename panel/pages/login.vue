<template>
  <div class="login-page">
    <PageLoader v-if="!ready" label="Loading…" class="login-loader" />

    <template v-else>
      <div class="login-top">
        <ThemeToggle />
      </div>

      <div class="login-card card">
        <div class="login-brand">
          <div class="login-logo">
            <AppIcon name="dashboard" :size="28" />
          </div>
          <div>
            <h1>dpanel</h1>
            <p class="login-tagline">VPS control panel</p>
          </div>
        </div>

        <p class="login-subtitle">Sign in to manage websites and MariaDB</p>

        <div v-if="error" class="alert alert-error">{{ error }}</div>

        <form class="login-form" @submit.prevent="submit">
          <div class="field">
            <label class="label" for="email">Email</label>
            <div class="input-wrap">
              <AppIcon name="mail" :size="18" class="input-icon" />
              <input
                id="email"
                v-model="email"
                class="input input-with-icon"
                type="email"
                required
                autocomplete="username"
                placeholder="admin@example.com"
              />
            </div>
          </div>
          <div class="field">
            <label class="label" for="password">Password</label>
            <div class="input-wrap">
              <AppIcon name="lock" :size="18" class="input-icon" />
              <input
                id="password"
                v-model="password"
                class="input input-with-icon"
                type="password"
                required
                autocomplete="current-password"
                placeholder="••••••••"
              />
            </div>
          </div>
          <button class="btn btn-primary login-submit" type="submit" :disabled="loading">
            <span v-if="loading" class="login-btn-inner">
              <span class="login-btn-spinner" aria-hidden="true" />
              Signing in…
            </span>
            <span v-else>Sign in</span>
          </button>
        </form>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: false })

const { initTheme } = useTheme()
const ready = ref(false)
const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

onMounted(async () => {
  initTheme()
  try {
    const me = await $fetch<{ authenticated?: boolean }>('/api/auth/me')
    if (me?.authenticated) {
      await navigateTo('/')
      return
    }
  } catch {
    /* show login form */
  }
  ready.value = true
})

async function submit() {
  error.value = ''
  loading.value = true
  try {
    await $fetch('/api/auth/login', {
      method: 'POST',
      body: { email: email.value, password: password.value }
    })
    await navigateTo('/')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    error.value = err.data?.statusMessage || err.statusMessage || 'Sign in failed'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-page {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 1.5rem;
  background: var(--bg);
  background-image: var(--login-glow);
  position: relative;
}

.login-loader {
  min-height: 100vh;
}

.login-page::before {
  content: '';
  position: absolute;
  inset: 0;
  background-image: radial-gradient(circle at 20% 80%, var(--accent-muted) 0%, transparent 40%),
    radial-gradient(circle at 80% 20%, var(--accent-muted) 0%, transparent 35%);
  pointer-events: none;
  opacity: 0.6;
}

.login-top {
  position: absolute;
  top: 1.25rem;
  right: 1.25rem;
  z-index: 2;
}

.login-card {
  position: relative;
  z-index: 1;
  width: 100%;
  max-width: 420px;
  padding: 2rem 1.75rem;
  box-shadow: var(--shadow-lg);
}

.login-brand {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1.25rem;
}

.login-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 3rem;
  height: 3rem;
  border-radius: 12px;
  background: var(--accent-muted);
  color: var(--accent);
  border: 1px solid var(--border);
}

.login-brand h1 {
  font-size: 1.5rem;
  margin: 0;
  letter-spacing: -0.03em;
}

.login-tagline {
  font-size: 0.8rem;
  color: var(--muted);
  margin-top: 0.15rem;
}

.login-subtitle {
  color: var(--muted);
  font-size: 0.9rem;
  margin-bottom: 1.5rem;
}

.login-form {
  margin-top: 0.25rem;
}

.input-wrap {
  position: relative;
}

.input-icon {
  position: absolute;
  left: 0.75rem;
  top: 50%;
  transform: translateY(-50%);
  color: var(--muted);
  pointer-events: none;
}

.input-with-icon {
  padding-left: 2.5rem;
}

.login-submit {
  width: 100%;
  margin-top: 0.35rem;
  padding-top: 0.7rem;
  padding-bottom: 0.7rem;
  font-size: 0.95rem;
}

.login-btn-inner {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
}

.login-btn-spinner {
  width: 1rem;
  height: 1rem;
  border: 2px solid rgba(255, 255, 255, 0.35);
  border-top-color: #fff;
  border-radius: 50%;
  animation: login-spin 0.7s linear infinite;
}

@keyframes login-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
