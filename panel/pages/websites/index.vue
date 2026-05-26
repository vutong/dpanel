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
            <th class="created-col">Created</th>
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
            <td class="created-col">{{ formatDate(s.createdAt) }}</td>
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
                  icon="eye"
                  title="View logs"
                  @click="openLogView(s)"
                />
                <IconButton
                  v-if="s.runtime === 'node'"
                  icon="edit"
                  title="Edit .env"
                  :disabled="isSiteBusy(s.domain)"
                  @click="openEnvEdit(s)"
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

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" />

    <SiteOpStreamModal
      :open="!!streamOp"
      :domain="streamOp?.domain ?? ''"
      :op="streamOp?.op ?? 'rebuild'"
      @close="onStreamClose"
      @done="onStreamDone"
    />

    <SiteEnvEditModal
      :open="!!envEditDomain"
      :domain="envEditDomain ?? ''"
      @close="closeEnvEdit"
      @saved="onEnvSaved"
    />

    <SiteLogViewModal
      :open="!!logViewDomain"
      :domain="logViewDomain ?? ''"
      @close="closeLogView"
    />

    <div v-if="updateTarget" class="modal-backdrop" @click.self="closeUpdate">
      <div class="modal card" role="dialog" aria-labelledby="update-title">
        <h2 id="update-title">Update from Git</h2>
        <p class="muted">
          Pull latest code for <strong>{{ updateTarget.domain }}</strong>
          <span v-if="updateTarget.githubUrl" class="repo-url">{{ updateTarget.githubUrl }}</span>
        </p>
        <div class="field">
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
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="closeUpdate">Cancel</button>
          <button type="button" class="btn btn-primary" @click="confirmUpdate">Pull from Git</button>
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
type SiteOpKind = 'update' | 'rebuild'

const { data, pending, refresh } = useFetch<{ sites: Site[] }>('/api/websites')
const sites = computed(() => data.value?.sites ?? [])
const hiddenDomains = ref<Set<string>>(new Set())
const displaySites = computed(() =>
  sites.value.filter((s) => !hiddenDomains.value.has(s.domain))
)

const deleteTarget = ref<Site | null>(null)
const deletePhase = ref<'confirm' | 'background'>('confirm')
const updateTarget = ref<Site | null>(null)
const updateToken = ref('')
const streamOp = ref<{ domain: string; op: SiteOpKind } | null>(null)
const envEditDomain = ref<string | null>(null)
const logViewDomain = ref<string | null>(null)
const opsRunning = ref<Set<string>>(new Set())
const busy = ref('')
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

function isSiteBusy(domain: string) {
  return opsRunning.value.has(domain)
}

function markOpRunning(domain: string) {
  opsRunning.value = new Set([...opsRunning.value, domain])
}

function markOpIdle(domain: string) {
  const next = new Set(opsRunning.value)
  next.delete(domain)
  opsRunning.value = next
}

function openStream(domain: string, op: SiteOpKind) {
  markOpRunning(domain)
  streamOp.value = { domain, op }
}

function onStreamClose() {
  if (streamOp.value) markOpIdle(streamOp.value.domain)
  streamOp.value = null
}

function onStreamDone(payload: { ok: boolean; message: string }) {
  if (streamOp.value) markOpIdle(streamOp.value.domain)
  streamOp.value = null
  showAlert(payload.message, payload.ok, payload.ok ? 8000 : 0)
}

function slug(domain: string) {
  return domain.replace(/\./g, '-').replace(/[^a-zA-Z0-9-]/g, '')
}

function openLogView(site: Site) {
  if (site.runtime !== 'node') return
  logViewDomain.value = site.domain
}

function closeLogView() {
  logViewDomain.value = null
}

function openEnvEdit(site: Site) {
  if (site.runtime !== 'node') return
  clearAlert()
  envEditDomain.value = site.domain
}

function closeEnvEdit() {
  envEditDomain.value = null
}

function onEnvSaved(payload: { restarted: boolean }) {
  const domain = envEditDomain.value
  envEditDomain.value = null
  if (!domain) return
  showAlert(
    payload.restarted
      ? `${domain}: .env saved and app restarted`
      : `${domain}: .env saved — restart app or Rebuild to apply`,
    true,
    8000
  )
}

function openUpdate(site: Site) {
  updateTarget.value = site
  updateToken.value = ''
  clearAlert()
}

function closeUpdate() {
  updateTarget.value = null
}

async function confirmUpdate() {
  const site = updateTarget.value
  if (!site) return

  const domain = site.domain
  clearAlert()

  try {
    await $fetch(`/api/websites/${encodeURIComponent(domain)}/update`, {
      method: 'POST',
      body: { githubToken: updateToken.value.trim() || undefined }
    })
    closeUpdate()
    openStream(domain, 'update')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not start pull', false)
  }
}

async function runRebuild(site: Site) {
  if (site.runtime !== 'node' || isSiteBusy(site.domain)) return

  const domain = site.domain
  clearAlert()

  try {
    await $fetch(`/api/websites/${encodeURIComponent(domain)}/rebuild`, { method: 'POST' })
    openStream(domain, 'rebuild')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not start rebuild', false)
  }
}

function openDelete(site: Site) {
  deleteTarget.value = site
  deletePhase.value = 'confirm'
  clearAlert()
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
  clearAlert()

  void $fetch(`/api/websites/${encodeURIComponent(domain)}`, { method: 'DELETE' })
    .catch((e: unknown) => {
      const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
      const raw = err.data?.statusMessage || err.statusMessage || ''
      showAlert(raw || `Could not start delete for ${domain}`, false)
    })
    .finally(() => {
      window.setTimeout(() => {
        void refresh().then(() => {
          if (sites.value.some((s) => s.domain === domain)) {
            const restored = new Set(hiddenDomains.value)
            restored.delete(domain)
            hiddenDomains.value = restored
            showAlert(
              `${domain} is still listed — try Delete again or: sudo dpanel site-remove ${domain}`,
              false
            )
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
.created-col {
  font-size: 0.82rem;
  color: var(--muted);
  white-space: nowrap;
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
