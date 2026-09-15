<template>
  <div>
    <h1>Create website</h1>
    <p class="muted">Enter domain and runtime. Optionally clone application code from GitHub.</p>
    <div v-if="resuming" class="alert alert-info">
      Resuming {{ streamOp === 'rebuild' ? 'build' : 'create' }} for
      <strong>{{ createdDomain }}</strong> — log continues below.
    </div>
    <div v-if="message" :class="['alert', ok ? 'alert-success' : 'alert-error']">
      {{ message }}
      <p v-if="!ok && createFailedHint" class="error-hint">{{ createFailedHint }}</p>
    </div>
    <form class="card form" @submit.prevent="submit">
      <div class="field">
        <label class="label">Domain</label>
        <input v-model="domain" class="input" placeholder="app.example.com" required />
      </div>
      <div class="field">
        <label class="label">Runtime</label>
        <select v-model="runtime" class="select" required>
          <option disabled value="">Select runtime</option>
          <option value="node">Node (Nuxt, Next..)</option>
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

    <SiteOpStreamModal
      :open="streamOpen"
      :domain="createdDomain"
      :op="streamOp"
      :resume="streamResume"
      @close="onStreamClose"
      @done="onStreamDone"
    />
  </div>
</template>

<script setup lang="ts">
import type { SiteOpKind } from '~/components/SiteOpStreamModal.vue'

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
const createFailedHint = ref('')
const gitTokenStorage = useGitHubTokenStorage()
const createOpSession = useCreateOpSession()
const streamOpen = ref(false)
const streamOp = ref<SiteOpKind>('create')
const streamResume = ref(false)
const resuming = ref(false)
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

function openCreateStream(domainNorm: string, op: SiteOpKind, resume: boolean) {
  createdDomain.value = domainNorm
  streamOp.value = op
  streamResume.value = resume
  resuming.value = resume
  streamOpen.value = true
  createOpSession.save({
    domain: domainNorm,
    op: op === 'rebuild' ? 'rebuild' : 'create',
    runtime: runtime.value,
    buildApp: buildApp.value
  })
}

async function resumePendingCreate() {
  const pending = createOpSession.load()
  if (!pending?.domain) return

  try {
    const s = await $fetch<{ status?: string; op?: string }>(
      `/api/websites/${encodeURIComponent(pending.domain)}/operation`
    )
    const op =
      s.op === 'rebuild' ? 'rebuild' : s.op === 'create' ? 'create' : pending.op
    if (s.status === 'running' && (op === 'create' || op === 'rebuild')) {
      domain.value = pending.domain
      runtime.value = pending.runtime
      buildApp.value = pending.buildApp
      cloneGithub.value = true
      openCreateStream(pending.domain, op, true)
      return
    }
    if ((s.status === 'error' || s.status === 'ok') && (op === 'create' || op === 'rebuild')) {
      domain.value = pending.domain
      runtime.value = pending.runtime
      buildApp.value = pending.buildApp
      cloneGithub.value = true
      openCreateStream(pending.domain, op, true)
      if (s.status === 'ok') createOpSession.clear()
      return
    }
    createOpSession.clear()
  } catch {
    /* no status — drop stale session */
    createOpSession.clear()
  }
}

onMounted(() => {
  if (!import.meta.client) return
  void resumePendingCreate()
})

async function submit() {
  message.value = ''
  createFailedHint.value = ''
  submitting.value = true
  ok.value = false
  streamResume.value = false
  resuming.value = false
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

    if (cloneGithub.value) {
      gitTokenStorage.persist(domainNorm, token, saveToken.value)
      openCreateStream(domainNorm, 'create', false)
      return
    }

    ok.value = true
    message.value =
      runtime.value === 'node'
        ? 'Website created. Deploy code if needed, then use Rebuild to build and run the Node SSR app.'
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

async function startRebuildAfterCreate() {
  try {
    await $fetch(`/api/websites/${encodeURIComponent(createdDomain.value)}/rebuild`, {
      method: 'POST',
      body: { nodeModulesMode: 'auto' }
    })
    streamOp.value = 'rebuild'
    streamResume.value = false
    createOpSession.updateOp('rebuild')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    ok.value = true
    message.value =
      err.data?.statusMessage ||
      err.statusMessage ||
      'Website created but could not start build — open the site and use Rebuild.'
    streamOpen.value = false
    createOpSession.clear()
    await navigateTo(`/websites/${encodeURIComponent(createdDomain.value)}`)
  }
}

function onStreamClose(payload?: { terminal?: boolean }) {
  streamOpen.value = false
  streamResume.value = false
  resuming.value = false
  if (payload?.terminal) createOpSession.clear()
  void navigateTo('/websites')
}

async function onStreamDone(payload: { ok: boolean; message: string }) {
  ok.value = payload.ok
  message.value = payload.message

  if (!payload.ok) {
    createFailedHint.value =
      streamOp.value === 'create'
        ? 'Fix the repository URL or token and try Create again. If the domain already appears under Websites, open it and use Update from Git — or delete the site and recreate.'
        : 'Open the site page and use Rebuild to try again.'
    return
  }

  createFailedHint.value = ''
  createOpSession.clear()

  if (streamOp.value === 'create') {
    const shouldBuild = buildApp.value && runtime.value === 'node'
    if (shouldBuild) {
      await startRebuildAfterCreate()
      return
    }
    streamOpen.value = false
    await navigateTo(
      runtime.value === 'node'
        ? `/websites/${encodeURIComponent(createdDomain.value)}`
        : '/websites'
    )
    return
  }

  streamOpen.value = false
  await navigateTo(`/websites/${encodeURIComponent(createdDomain.value)}`)
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
.error-hint {
  margin: 0.5rem 0 0;
  font-size: 0.82rem;
  line-height: 1.45;
  opacity: 0.95;
}
</style>
