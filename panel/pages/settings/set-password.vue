<template>
  <div>
    <h1>Set Password</h1>
    <p class="page-desc">
      Change the panel login password for
      <strong v-if="email">{{ email }}</strong>
      <span v-else class="skeleton skeleton-text" style="width: 10rem" aria-hidden="true" />.
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <form class="card form" @submit.prevent="submit">
      <div class="field">
        <label class="label" for="current-password">Current password</label>
        <input
          id="current-password"
          v-model="currentPassword"
          class="input"
          type="password"
          required
          autocomplete="current-password"
        />
      </div>
      <div class="field">
        <label class="label" for="new-password">New password</label>
        <input
          id="new-password"
          v-model="newPassword"
          class="input"
          type="password"
          required
          minlength="8"
          autocomplete="new-password"
        />
        <p class="hint">At least 8 characters.</p>
      </div>
      <div class="field">
        <label class="label" for="confirm-password">Confirm new password</label>
        <input
          id="confirm-password"
          v-model="confirmPassword"
          class="input"
          type="password"
          required
          minlength="8"
          autocomplete="new-password"
        />
      </div>
      <button class="btn btn-primary" type="submit" :disabled="submitting">
        {{ submitting ? 'Updating…' : 'Update password' }}
      </button>
    </form>
  </div>
</template>

<script setup lang="ts">
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

const email = ref('')
const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const submitting = ref(false)

onMounted(async () => {
  try {
    const me = await $fetch<{ email?: string | null }>('/api/auth/me')
    email.value = me.email || ''
  } catch {
    /* auth middleware handles redirect */
  }
})

async function submit() {
  clearAlert()

  if (newPassword.value !== confirmPassword.value) {
    showAlert('New password and confirmation do not match', false)
    return
  }

  submitting.value = true
  try {
    await $fetch('/api/auth/set-password', {
      method: 'POST',
      body: {
        currentPassword: currentPassword.value,
        newPassword: newPassword.value
      }
    })
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    showAlert('Password updated successfully.', true)
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Failed to update password', false)
  } finally {
    submitting.value = false
  }
}
</script>

<style scoped>
.page-desc {
  color: var(--muted);
  margin: 0.35rem 0 1.25rem;
}

.form {
  max-width: 480px;
  margin: 1rem 0;
}

.hint {
  color: var(--muted);
  font-size: 0.82rem;
  margin-top: 0.35rem;
}
</style>
