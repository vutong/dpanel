<template>
  <div>
    <div class="header">
      <h1>Websites</h1>
      <NuxtLink to="/websites/create" class="btn btn-primary">+ Create website</NuxtLink>
    </div>

    <PageLoader v-if="pending" label="Loading websites…" />
    <div v-else-if="!displaySites.length" class="card muted">No websites yet. Create your first site.</div>
    <div v-else class="card table-wrap">
      <table class="table">
        <thead>
          <tr>
            <th>Domain</th>
            <th>Runtime</th>
            <th>GitHub</th>
            <th>Created</th>
            <th class="col-actions">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="s in displaySites" :key="s.domain">
            <td><strong>{{ s.domain }}</strong></td>
            <td>
              <span :class="s.runtime === 'node' ? 'badge badge-node' : 'badge badge-php'">
                {{ s.runtime }}
              </span>
            </td>
            <td class="github-cell">{{ s.githubUrl || '—' }}</td>
            <td>{{ formatDate(s.createdAt) }}</td>
            <td class="col-actions">
              <div class="action-btns">
                <IconButton
                  v-if="s.githubUrl"
                  icon="git-pull"
                  title="Update from Git"
                  :disabled="isSiteBusy(s.domain)"
                  :busy="isSiteBusy(s.domain)"
                  @click="openUpdate(s)"
                />
                <IconButton
                  v-if="s.runtime === 'node'"
                  icon="wrench"
                  title="Rebuild (npm build)"
                  :disabled="isSiteBusy(s.domain)"
                  :busy="isSiteBusy(s.domain)"
                  @click="runRebuild(s)"
                />
                <IconButton
                  icon="trash"
                  title="Delete website"
                  variant="danger"
                  :disabled="!!busy"
                  :busy="busy === s.domain"
                  @click="openDelete(s)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <p v-if="msg" class="alert" :class="ok ? 'alert-success' : 'alert-error'">{{ msg }}</p>

    <div v-if="updateTarget" class="modal-backdrop" @click.self="closeUpdate">
      <div class="modal card" role="dialog" aria-labelledby="update-title">
        <h2 id="update-title">Update from Git</h2>
        <p class="muted">
          Pull latest code for <strong>{{ updateTarget.domain }}</strong>
          <span v-if="updateTarget.githubUrl" class="repo-url">{{ updateTarget.githubUrl }}</span>
        </p>
        <div v-if="updatePhase === 'confirm'" class="field">
          <label class="label">GitHub token (PAT)</label>
          <input
            v-model="updateToken"
            class="input"
            type="password"
            placeholder="Required for private repos; leave empty if public"
            autocomplete="off"
          />
          <p class="hint">
            Token is not stored. If pull fails with 401/403, your PAT may be <strong>expired</strong> — create a new one
            (<code>ghp_...</code> with <code>repo</code> scope).
          </p>
        </div>
        <p v-else class="alert alert-info delete-running">
          Pull is running in the background.
        </p>
        <div class="modal-actions">
          <button
            v-if="updatePhase === 'confirm'"
            type="button"
            class="btn btn-ghost"
            @click="closeUpdate"
          >
            Cancel
          </button>
          <button v-else type="button" class="btn btn-primary" @click="closeUpdate">
            Close
          </button>
          <button
            v-if="updatePhase === 'confirm'"
            type="button"
            class="btn btn-primary"
            @click="confirmUpdate"
          >
            Pull from Git
          </button>
        </div>
      </div>
    </div>

    <div v-if="deleteTarget" class="modal-backdrop" @click.self="closeDelete">
      <div class="modal card" role="dialog" aria-labelledby="delete-title">
        <h2 id="delete-title">Delete website</h2>
        <p class="muted">
          Remove <strong>{{ deleteTarget.domain }}</strong> from the panel and stack.
        </p>
        <ul v-if="deletePhase === 'confirm'" class="delete-list">
          <li>Panel registry (<code>sites.json</code>)</li>
          <li>Nginx vhost (<code>conf.d/</code> and <code>conf.d/disabled/</code>)</li>
          <li><code>apps/{{ deleteTarget.domain }}/</code> (application files)</li>
          <li v-if="deleteTarget.runtime === 'node'">
            Docker <code>nuxt-{{ slug(deleteTarget.domain) }}</code> and
            <code>compose.d/nuxt-{{ slug(deleteTarget.domain) }}.yml</code>
          </li>
        </ul>
        <p v-if="deletePhase === 'confirm'" class="hint">
          This permanently removes all related files and cannot be undone.
        </p>
        <p v-else class="alert alert-info delete-running">
          Deletion is running automatically.
        </p>
        <div class="modal-actions">
          <button
            v-if="deletePhase === 'confirm'"
            type="button"
            class="btn btn-ghost"
            :disabled="!!busy"
            @click="closeDelete"
          >
            Cancel
          </button>
          <button
            v-else
            type="button"
            class="btn btn-primary"
            @click="closeDelete"
          >
            Close
          </button>
          <button
            v-if="deletePhase === 'confirm'"
            type="button"
            class="btn btn-danger"
            :disabled="!!busy"
            @click="confirmDelete"
          >
            Delete website
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
type SiteOpStatus = {
  domain?: string
  op?: string
  status: 'none' | 'running' | 'ok' | 'error'
  message?: string
}

const { data, pending, refresh } = useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])
const hiddenDomains = ref<Set<string>>(new Set())
const displaySites = computed(() =>
  sites.value.filter((s) => !hiddenDomains.value.has(s.domain))
)

const deleteTarget = ref<Site | null>(null)
const deletePhase = ref<'confirm' | 'background'>('confirm')
const updateTarget = ref<Site | null>(null)
const updatePhase = ref<'confirm' | 'background'>('confirm')
const updateToken = ref('')
const opsRunning = ref<Set<string>>(new Set())
const pollTimers = new Map<string, ReturnType<typeof setInterval>>()
const busy = ref('')
const msg = ref('')
const ok = ref(false)

onUnmounted(() => {
  for (const t of pollTimers.values()) clearInterval(t)
  pollTimers.clear()
})

function isSiteBusy(domain: string) {
  return opsRunning.value.has(domain)
}

function stopOpPoll(domain: string) {
  const t = pollTimers.get(domain)
  if (t) clearInterval(t)
  pollTimers.delete(domain)
  const next = new Set(opsRunning.value)
  next.delete(domain)
  opsRunning.value = next
}

function startOpPoll(domain: string) {
  if (pollTimers.has(domain)) return
  opsRunning.value = new Set([...opsRunning.value, domain])
  let attempts = 0
  const maxAttempts = 240

  const poll = async () => {
    attempts += 1
    if (attempts > maxAttempts) {
      stopOpPoll(domain)
      ok.value = false
      msg.value = `${domain}: operation timed out — check logs/node on the server`
      return
    }
    try {
      const s = await $fetch<SiteOpStatus>(
        `/api/websites/${encodeURIComponent(domain)}/operation`
      )
      if (s.status === 'running' || s.status === 'none') return
      stopOpPoll(domain)
      if (s.status === 'ok') {
        ok.value = true
        msg.value = s.message || `Done: ${domain}`
        if (updateTarget.value?.domain === domain) {
          updateTarget.value = null
          updatePhase.value = 'confirm'
        }
      } else if (s.status === 'error') {
        ok.value = false
        msg.value = s.message || `Failed: ${domain}`
      }
    } catch {
      /* keep polling */
    }
  }

  void poll()
  const timer = setInterval(() => void poll(), 2500)
  pollTimers.set(domain, timer)
}

function slug(domain: string) {
  return domain.replace(/\./g, '-').replace(/[^a-zA-Z0-9-]/g, '')
}

function openUpdate(site: Site) {
  updateTarget.value = site
  updatePhase.value = 'confirm'
  updateToken.value = ''
  msg.value = ''
}

function closeUpdate() {
  updateTarget.value = null
  updatePhase.value = 'confirm'
}

function confirmUpdate() {
  const site = updateTarget.value
  if (!site || updatePhase.value !== 'confirm') return

  const domain = site.domain
  updatePhase.value = 'background'
  msg.value = ''

  void $fetch(`/api/websites/${encodeURIComponent(domain)}/update`, {
    method: 'POST',
    body: { githubToken: updateToken.value.trim() || undefined }
  })
    .then(() => startOpPoll(domain))
    .catch((e: unknown) => {
      updatePhase.value = 'confirm'
      ok.value = false
      const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
      msg.value = err.data?.statusMessage || err.statusMessage || 'Could not start pull'
    })
}

function runRebuild(site: Site) {
  if (site.runtime !== 'node' || isSiteBusy(site.domain)) return

  const domain = site.domain
  ok.value = true
  msg.value = 'Rebuild is running in the background.'
  startOpPoll(domain)

  window.setTimeout(() => {
    void $fetch(`/api/websites/${encodeURIComponent(domain)}/rebuild`, { method: 'POST' }).catch(
      (e: unknown) => {
        stopOpPoll(domain)
        ok.value = false
        const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
        msg.value = err.data?.statusMessage || err.statusMessage || 'Could not start rebuild'
      }
    )
  }, 0)
}

function openDelete(site: Site) {
  deleteTarget.value = site
  deletePhase.value = 'confirm'
  msg.value = ''
}

function closeDelete() {
  deleteTarget.value = null
  deletePhase.value = 'confirm'
}

function confirmDelete() {
  const site = deleteTarget.value
  if (!site || deletePhase.value !== 'confirm') return

  const domain = site.domain
  const nextHidden = new Set(hiddenDomains.value)
  nextHidden.add(domain)
  hiddenDomains.value = nextHidden

  deletePhase.value = 'background'
  ok.value = true
  msg.value = ''

  void $fetch(`/api/websites/${encodeURIComponent(domain)}`, { method: 'DELETE' })
    .catch((e: unknown) => {
      const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
      const raw = err.data?.statusMessage || err.statusMessage || ''
      ok.value = false
      msg.value = raw || `Could not start delete for ${domain}`
    })
    .finally(() => {
      window.setTimeout(() => {
        void refresh().then(() => {
          if (sites.value.some((s) => s.domain === domain)) {
            const restored = new Set(hiddenDomains.value)
            restored.delete(domain)
            hiddenDomains.value = restored
            if (!msg.value || ok.value) {
              ok.value = false
              msg.value = `${domain} is still listed — try Delete again or: sudo dpanel site-remove ${domain}`
            }
          } else {
            const done = new Set(hiddenDomains.value)
            done.delete(domain)
            hiddenDomains.value = done
          }
        })
      }, 2500)
    })
}

function formatDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US')
}
</script>

<style scoped>
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.25rem;
  flex-wrap: wrap;
  gap: 0.75rem;
}
.muted { color: var(--muted); }
.table-wrap {
  overflow-x: auto;
}
.col-actions {
  text-align: right;
  white-space: nowrap;
  overflow: visible;
}
.action-btns {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  justify-content: flex-end;
  overflow: visible;
}
.github-cell {
  max-width: min(280px, 28vw);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 0.85rem;
}
.repo-url {
  display: block;
  font-size: 0.8rem;
  margin-top: 0.35rem;
  word-break: break-all;
}
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
  padding: 1rem;
}
.modal {
  width: 100%;
  max-width: 480px;
}
.modal h2 {
  margin-bottom: 0.75rem;
  font-size: 1.15rem;
}
.delete-list {
  margin: 1rem 0;
  padding-left: 1.25rem;
  color: var(--text);
  font-size: 0.9rem;
}
.delete-list li { margin-bottom: 0.35rem; }
.delete-list code {
  font-size: 0.8rem;
  color: var(--muted);
}
.hint {
  font-size: 0.8rem;
  color: var(--muted);
  margin-bottom: 1rem;
  line-height: 1.45;
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}
.delete-running {
  margin: 0.75rem 0 0;
  font-size: 0.9rem;
  line-height: 1.5;
}
</style>
