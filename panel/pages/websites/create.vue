<template>
  <div>
    <PageLoader v-if="pageLoading" label="Loading…" />
    <template v-else>
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
          <option disabled value="">Select runtime</option>
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
            <strong>Private repo:</strong> use a <strong>classic PAT</strong> (<code>ghp_...</code>, scope <code>repo</code>) — most reliable.
            Fine-grained (<code>github_pat_...</code>): select this repo + <strong>Contents: Read</strong>; org repos may need owner approval.<br>
            Token is sent via env for clone only (not saved). Revoke token if exposed.
          </p>
        </div>
      </template>
      <button class="btn btn-primary" type="submit" :disabled="submitting">
        {{ submitting ? 'Creating...' : 'Create & deploy' }}
      </button>
    </form>
    </template>
  </div>
</template>

<script setup lang="ts">
const { loading: pageLoading } = usePageInit()
const domain = ref('')
const runtime = ref('')
const cloneGithub = ref(false)
const githubUrl = ref('')
const githubToken = ref('')
const submitting = ref(false)
const message = ref('')
const ok = ref(false)

async function submit() {
  message.value = ''
  submitting.value = true
  ok.value = false
  try {
    if (!runtime.value) {
      message.value = 'Please select a runtime'
      submitting.value = false
      return
    }
    const url = cloneGithub.value ? githubUrl.value.trim() : ''
    const token = cloneGithub.value ? githubToken.value.trim() : ''
    if (cloneGithub.value && !url) {
      message.value = 'Repository URL is required when cloning from GitHub'
      submitting.value = false
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
    const err = e as {
      data?: { statusMessage?: string; message?: string }
      statusMessage?: string
      message?: string
      statusCode?: number
    }
    const raw =
      err.data?.statusMessage ||
      err.data?.message ||
      err.statusMessage ||
      err.message ||
      ''
    if (err.statusCode === 502 || /bad gateway/i.test(raw)) {
      message.value =
        'Gateway error — the site may still have been created. Wait a few seconds and check Websites, or run: sudo dpanel nginx-reload'
      await navigateTo('/websites')
    } else {
      message.value = raw || 'Failed to create website'
    }
  } finally {
    submitting.value = false
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
