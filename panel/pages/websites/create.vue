<template>
  <div>
    <h1>Create website</h1>
    <p class="muted">Enter domain and runtime. GitHub is optional — leave empty to only create folders and nginx.</p>
    <div v-if="message" :class="['alert', ok ? 'alert-success' : 'alert-error']">{{ message }}</div>
    <form class="card form" @submit.prevent="submit">
      <div class="field">
        <label class="label">Domain</label>
        <input v-model="domain" class="input" placeholder="app.example.com" required />
      </div>
      <div class="field">
        <label class="label">Runtime</label>
        <select v-model="runtime" class="select" required>
          <option value="node">Node (Nuxt SSR)</option>
          <option value="php">PHP (Laravel / WordPress)</option>
        </select>
      </div>
      <template v-if="runtime === 'php' || showGithub">
        <div class="field">
          <label class="label">GitHub URL (optional)</label>
          <input v-model="githubUrl" class="input" placeholder="https://github.com/user/repo.git" />
        </div>
        <div v-if="githubUrl" class="field">
          <label class="label">GitHub token / PAT (optional, private repos)</label>
          <input v-model="githubToken" class="input" type="password" placeholder="ghp_..." />
        </div>
      </template>
      <div v-if="runtime === 'node'" class="field">
        <label class="label">
          <input v-model="showGithub" type="checkbox" /> Clone from GitHub
        </label>
        <template v-if="showGithub">
          <input v-model="githubUrl" class="input" placeholder="https://github.com/user/repo.git" style="margin-top:0.5rem" />
          <input v-if="githubUrl" v-model="githubToken" class="input" type="password" placeholder="Token (private repo)" style="margin-top:0.5rem" />
        </template>
      </div>
      <button class="btn btn-primary" type="submit" :disabled="loading">
        {{ loading ? 'Creating...' : 'Create & deploy' }}
      </button>
    </form>
  </div>
</template>

<script setup lang="ts">
const domain = ref('')
const runtime = ref<'node' | 'php'>('php')
const githubUrl = ref('')
const githubToken = ref('')
const showGithub = ref(false)
const loading = ref(false)
const message = ref('')
const ok = ref(false)

async function submit() {
  message.value = ''
  loading.value = true
  ok.value = false
  try {
    await $fetch('/api/websites', {
      method: 'POST',
      body: {
        domain: domain.value.trim(),
        runtime: runtime.value,
        githubUrl: githubUrl.value.trim() || undefined,
        githubToken: githubToken.value.trim() || undefined
      }
    })
    ok.value = true
    message.value = 'Website created successfully.'
    await navigateTo('/websites')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    message.value = err.data?.statusMessage || err.statusMessage || 'Failed to create website'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.muted { color: var(--muted); margin: 0.5rem 0 1rem; }
.form { max-width: 520px; margin-top: 1rem; }
</style>
