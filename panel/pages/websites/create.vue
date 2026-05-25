<template>
  <div>
    <h1>Create website</h1>
    <p class="muted">Enter domain and runtime. Optionally clone application code from GitHub.</p>
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
      <div class="field">
        <label class="label checkbox-label">
          <input v-model="cloneGithub" type="checkbox" />
          Clone from GitHub
        </label>
      </div>
      <template v-if="cloneGithub">
        <div class="field">
          <label class="label">Repository URL</label>
          <input
            v-model="githubUrl"
            class="input"
            placeholder="https://github.com/user/repo.git"
            required
          />
        </div>
        <div class="field">
          <label class="label">GitHub token (PAT)</label>
          <input
            v-model="githubToken"
            class="input"
            type="password"
            placeholder="ghp_... or github_pat_..."
            autocomplete="off"
          />
          <p class="hint">
            <strong>Public repo:</strong> leave token empty.<br>
            <strong>Private repo:</strong> create a Personal Access Token on GitHub
            (Settings → Developer settings → Tokens). Classic token: enable <code>repo</code> scope.
            Fine-grained: read access to repository contents. The token is used only for
            <code>git clone</code> and is <strong>not stored</strong> on the server.
          </p>
        </div>
      </template>
      <button class="btn btn-primary" type="submit" :disabled="loading">
        {{ loading ? 'Creating...' : 'Create & deploy' }}
      </button>
    </form>
  </div>
</template>

<script setup lang="ts">
const domain = ref('')
const runtime = ref<'node' | 'php'>('php')
const cloneGithub = ref(false)
const githubUrl = ref('')
const githubToken = ref('')
const loading = ref(false)
const message = ref('')
const ok = ref(false)

async function submit() {
  message.value = ''
  loading.value = true
  ok.value = false
  try {
    const url = cloneGithub.value ? githubUrl.value.trim() : ''
    const token = cloneGithub.value ? githubToken.value.trim() : ''
    if (cloneGithub.value && !url) {
      message.value = 'Repository URL is required when cloning from GitHub'
      return
    }
    await $fetch('/api/websites', {
      method: 'POST',
      body: {
        domain: domain.value.trim(),
        runtime: runtime.value,
        githubUrl: url || undefined,
        githubToken: token || undefined
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
.checkbox-label { display: flex; align-items: center; gap: 0.5rem; font-weight: 500; cursor: pointer; }
.checkbox-label input { width: auto; }
.hint {
  margin: 0.5rem 0 0;
  font-size: 0.82rem;
  color: var(--muted);
  line-height: 1.45;
}
.hint code { font-size: 0.8rem; }
</style>
