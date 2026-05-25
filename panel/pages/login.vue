<template>
  <div class="login-wrap">
    <div class="card login-card">
      <h1>dpanel</h1>
      <p class="subtitle">Đăng nhập control panel</p>
      <div v-if="error" class="alert alert-error">{{ error }}</div>
      <form @submit.prevent="submit">
        <div class="field">
          <label class="label">Email</label>
          <input v-model="email" class="input" type="email" required autocomplete="username" />
        </div>
        <div class="field">
          <label class="label">Mật khẩu</label>
          <input v-model="password" class="input" type="password" required autocomplete="current-password" />
        </div>
        <button class="btn btn-primary" type="submit" :disabled="loading">
          {{ loading ? 'Đang đăng nhập...' : 'Đăng nhập' }}
        </button>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: false })

const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

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
    error.value = err.data?.statusMessage || err.statusMessage || 'Đăng nhập thất bại'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-wrap {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
}
.login-card { width: 100%; max-width: 400px; }
h1 { font-size: 1.75rem; margin-bottom: 0.25rem; }
.subtitle { color: var(--muted); margin-bottom: 1.5rem; font-size: 0.9rem; }
.btn-primary { width: 100%; justify-content: center; margin-top: 0.5rem; }
</style>
