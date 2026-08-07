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
      <div class="field github-row">
        <label class="checkbox-label">
          <input v-model="cloneGithub" type="checkbox" />
          Github
        </label>
        <label v-if="cloneGithub" class="checkbox-label">
          <input v-model="saveToken" type="checkbox" />
          Save token
        </label>
        <label v-if="cloneGithub && runtime === 'node'" class="checkbox-label">
          <input v-model="buildApp" type="checkbox" />
          Build App
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
            Token is sent via env for clone only. Tick <strong>Save token</strong> to remember it in this browser. Revoke token if exposed.
          </p>
        </div>
      </template>
      <button class="btn btn-primary" type="submit" :disabled="submitting || streamOpen">
        {{ submitting ? 'Creating...' : 'Create & deploy' }}
      </button>
    </form>
    </template>

    <SiteOpStreamModal
      :open="streamOpen"
      :domain="createdDomain"
      op="rebuild"
      @close="onBuildStreamClose"
      @done="onBuildStreamDone"
    />
  </div>
</template>

<script setup lang="ts">
const { loading: pageLoading } = usePageInit()
const domain = ref('')
const runtime = ref('')
const cloneGithub = ref(false)
const saveToken = ref(false)
const buildApp = ref(false)
const githubUrl = ref('')
const githubToken = ref('')
const submitting = ref(false)
const message = ref('')
const ok = ref(false)
const gitTokenStorage = useGitHubTokenStorage()
const streamOpen = ref(false)
const createdDomain = ref('')

watch(runtime, (v) => {
  if (v !== 'node') buildApp.value = false
})

watch(cloneGithub, (v) => {
  if (!v) {
    saveToken.value = false
    buildApp.value = false
  }
})

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
    const domainNorm = domain.value.trim().toLowerCase()
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
        domain: domainNorm,
        runtime: runtime.value,
        githubUrl: url || undefined,
        githubToken: token || undefined
      }
    })
    ok.value = true

    if (cloneGithub.value) {
      gitTokenStorage.persist(domainNorm, token, saveToken.value)
    }

    const shouldBuild = cloneGithub.value && buildApp.value && runtime.value === 'node'
    if (shouldBuild) {
      message.value = 'Website created. Starting build…'
      createdDomain.value = domainNorm
      try {
        await $fetch(`/api/websites/${encodeURIComponent(domainNorm)}/rebuild`, {
          method: 'POST',
          body: { nodeModulesMode: 'auto' }
        })
        streamOpen.value = true
      } catch (e: unknown) {
        const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
        message.value =
          err.data?.statusMessage ||
          err.statusMessage ||
          'Website created but could not start build — open the site and use Rebuild.'
        await navigateTo(`/websites/${encodeURIComponent(domainNorm)}`)
      }
      return
    }

    message.value =
      runtime.value === 'node'
        ? 'Website created. Deploy code if needed, then use Rebuild to build and run the Nuxt app.'
        : 'Website created successfully.'
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

function onBuildStreamClose() {
  streamOpen.value = false
  void navigateTo(`/websites/${encodeURIComponent(createdDomain.value)}`)
}

function onBuildStreamDone(payload: { ok: boolean; message: string }) {
  ok.value = payload.ok
  message.value = payload.message
  if (payload.ok) {
    streamOpen.value = false
    void navigateTo(`/websites/${encodeURIComponent(createdDomain.value)}`)
  }
}
</script>

<style scoped>
.muted { color: var(--muted); margin: 0.5rem 0 1rem; }
.form { max-width: 520px; margin-top: 1rem; }
.github-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 1rem 1.25rem;
}
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
