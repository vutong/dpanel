<template>
  <div class="site-manager">
    <nav class="breadcrumb">
      <NuxtLink to="/websites" class="crumb-link">
        <AppIcon name="arrow-left" :size="16" />
        Websites
      </NuxtLink>
    </nav>

    <PageLoader v-if="pending" label="Loading site…" />
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else-if="site">
      <header class="site-header card">
        <div class="site-header-main">
          <h1>{{ site.domain }}</h1>
          <span :class="site.runtime === 'node' ? 'badge badge-node' : 'badge badge-php'">
            {{ site.runtime }}
          </span>
        </div>
        <dl class="meta-grid">
          <div>
            <dt>Created</dt>
            <dd>{{ formatDate(site.createdAt) }}</dd>
          </div>
          <div v-if="site.runtime === 'node' && resources">
            <dt>Container limits</dt>
            <dd>{{ limitsSummary }}</dd>
          </div>
          <div v-if="site.githubUrl">
            <dt>GitHub</dt>
            <dd>
              <a
                :href="site.githubUrl"
                class="meta-ellipsis"
                target="_blank"
                rel="noopener noreferrer"
                :title="site.githubUrl"
              >{{ site.githubUrl }}</a>
            </dd>
          </div>
        </dl>
      </header>

      <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

      <section class="section">
        <h2 class="section-title">Deploy &amp; code</h2>
        <div class="tile-grid">
          <button
            v-if="site.githubUrl"
            type="button"
            class="tile"
            :disabled="busy"
            @click="openUpdate"
          >
            <AppIcon name="git-pull" :size="22" />
            <span class="tile-title">Update from Git</span>
            <span class="tile-desc">Pull latest commit</span>
          </button>
          <button
            v-if="site.runtime === 'node'"
            type="button"
            class="tile"
            :disabled="busy"
            @click="openRebuild"
          >
            <AppIcon name="wrench" :size="22" />
            <span class="tile-title">Rebuild</span>
            <span class="tile-desc">npm install &amp; build</span>
          </button>
          <button
            v-if="site.runtime === 'node' && site.githubUrl"
            type="button"
            class="tile"
            :disabled="busy"
            @click="openFullUpdate"
          >
            <AppIcon name="layers" :size="22" />
            <span class="tile-title">Update</span>
            <span class="tile-desc">Pull from Git then rebuild</span>
          </button>
          <div v-if="!site.githubUrl && site.runtime !== 'node'" class="tile tile--muted">
            <AppIcon name="git-pull" :size="22" />
            <span class="tile-title">No Git remote</span>
            <span class="tile-desc">Upload files to apps/{{ site.domain }}/</span>
          </div>
        </div>
      </section>

      <section v-if="site.runtime === 'node'" class="section">
        <h2 class="section-title">Configuration</h2>
        <div class="tile-grid">
          <button type="button" class="tile" :disabled="busy" @click="routingOpen = true">
            <AppIcon name="globe" :size="22" />
            <span class="tile-title">Wildcard</span>
            <span class="tile-desc">Wildcard &amp; DNS</span>
          </button>
          <button type="button" class="tile" :disabled="busy" @click="envOpen = true">
            <AppIcon name="edit" :size="22" />
            <span class="tile-title">Environment</span>
            <span class="tile-desc">Edit .env</span>
          </button>
          <button type="button" class="tile" :disabled="busy" @click="resourcesOpen = true">
            <AppIcon name="cpu" :size="22" />
            <span class="tile-title">Resources</span>
            <span class="tile-desc">CPU, RAM, disk limits</span>
          </button>
        </div>
      </section>

      <section v-if="site.runtime === 'node'" class="section">
        <h2 class="section-title">Monitoring</h2>
        <div class="tile-grid">
          <button type="button" class="tile" @click="logOpen = true">
            <AppIcon name="eye" :size="22" />
            <span class="tile-title">Application logs</span>
            <span class="tile-desc">Build &amp; container output</span>
          </button>
        </div>
      </section>

      <section class="section">
        <h2 class="section-title">Coming soon</h2>
        <p class="section-intro">Planned areas for future releases — not available yet.</p>
        <div class="tile-grid tile-grid--soon">
          <div v-for="item in comingSoon" :key="item.title" class="tile tile--soon">
            <AppIcon :name="item.icon" :size="22" />
            <span class="tile-title">{{ item.title }}</span>
            <span class="tile-desc">{{ item.desc }}</span>
            <span class="soon-badge">Soon</span>
          </div>
        </div>
      </section>

      <section class="section section--danger">
        <button type="button" class="btn-delete-quiet" :disabled="busy" @click="openDelete">
          Delete website…
        </button>
      </section>
    </template>

    <SiteOpStreamModal
      :open="!!streamOp"
      :domain="domainParam"
      :op="streamOp ?? 'rebuild'"
      @close="onStreamClose"
      @done="onStreamDone"
    />
    <SiteEnvEditModal :open="envOpen" :domain="domainParam" @close="envOpen = false" @saved="onEnvSaved" />
    <SiteLogViewModal :open="logOpen" :domain="domainParam" @close="logOpen = false" />
    <SiteRoutingModal
      :open="routingOpen"
      :domain="domainParam"
      @close="routingOpen = false"
      @saved="onRoutingSaved"
    />
    <SiteResourcesModal
      :open="resourcesOpen"
      :domain="domainParam"
      @close="resourcesOpen = false"
      @saved="onResourcesSaved"
    />

    <div v-if="rebuildOpen" class="modal-backdrop" @click.self="rebuildOpen = false">
      <div class="modal card rebuild-modal" role="dialog" aria-labelledby="rebuild-title">
        <h2 id="rebuild-title">Rebuild</h2>
        <p class="muted rebuild-intro">
          <code>npm install</code> and <code>npm run build</code> for <strong>{{ site?.domain }}</strong>.
          Choose how dependencies are handled.
        </p>

        <fieldset class="rebuild-mode-group">
          <legend class="label">node_modules</legend>
          <label
            v-for="opt in rebuildModeOptions"
            :key="opt.value"
            class="rebuild-mode-option"
            :class="{ 'rebuild-mode-option--active': nodeModulesMode === opt.value }"
          >
            <input
              v-model="nodeModulesMode"
              class="rebuild-mode-input"
              type="radio"
              name="node-modules-mode"
              :value="opt.value"
            />
            <span class="rebuild-mode-body">
              <span class="rebuild-mode-title">
                {{ opt.title }}
                <span v-if="opt.recommended" class="rebuild-mode-badge">Recommended</span>
              </span>
              <span class="rebuild-mode-desc">{{ opt.desc }}</span>
            </span>
          </label>
        </fieldset>

        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="rebuildOpen = false">Cancel</button>
          <button type="button" class="btn btn-primary" :disabled="busy" @click="confirmRebuild">
            Start rebuild
          </button>
        </div>
      </div>
    </div>

    <div v-if="updateOpen" class="modal-backdrop" @click.self="closeUpdateModal">
      <div class="modal card" :class="{ 'rebuild-modal': updateMode === 'full' }" role="dialog">
        <h2>{{ updateMode === 'full' ? 'Update' : 'Update from Git' }}</h2>
        <p class="muted">
          <template v-if="updateMode === 'full'">
            Pull latest code then rebuild <strong>{{ site?.domain }}</strong>
          </template>
          <template v-else>
            Pull latest code for <strong>{{ site?.domain }}</strong>
          </template>
        </p>
        <div class="field">
          <label class="label">Repository URL</label>
          <input
            v-model="updateGithubUrl"
            class="input"
            type="url"
            placeholder="https://github.com/user/repo.git"
            autocomplete="off"
          />
        </div>
        <div class="field">
          <label class="label">GitHub token (PAT)</label>
          <input v-model="updateToken" class="input" type="password" autocomplete="off" />
        </div>
        <div class="field update-options">
          <label class="checkbox-label">
            <input v-model="updateSaveToken" type="checkbox" />
            Save token
          </label>
          <p class="hint">Remember in this browser and fill the field next time.</p>
          <label class="checkbox-label">
            <input v-model="updateGitCheckout" type="checkbox" />
            Checkout (git)
          </label>
          <p class="hint">
            Run <code>git restore .</code> before pull — discards local changes (e.g. after Rebuild modified
            <code>package-lock.json</code>).
          </p>
        </div>
        <fieldset v-if="updateMode === 'full'" class="rebuild-mode-group">
          <legend class="label">node_modules</legend>
          <label
            v-for="opt in rebuildModeOptions"
            :key="opt.value"
            class="rebuild-mode-option"
            :class="{ 'rebuild-mode-option--active': nodeModulesMode === opt.value }"
          >
            <input
              v-model="nodeModulesMode"
              class="rebuild-mode-input"
              type="radio"
              name="full-update-node-modules-mode"
              :value="opt.value"
            />
            <span class="rebuild-mode-body">
              <span class="rebuild-mode-title">
                {{ opt.title }}
                <span v-if="opt.recommended" class="rebuild-mode-badge">Recommended</span>
              </span>
              <span class="rebuild-mode-desc">{{ opt.desc }}</span>
            </span>
          </label>
        </fieldset>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="closeUpdateModal">Cancel</button>
          <button type="button" class="btn btn-primary" :disabled="busy" @click="confirmUpdate">
            {{ updateMode === 'full' ? 'Update' : 'Pull from Git' }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="deleteOpen" class="modal-backdrop" @click.self="closeDelete">
      <div class="modal card" role="dialog" aria-labelledby="delete-title">
        <h2 id="delete-title">Delete website</h2>
        <template v-if="deletePhase === 'confirm'">
          <p class="muted">
            This permanently removes <strong>{{ site?.domain }}</strong> and cannot be undone.
          </p>
          <ul class="delete-list">
            <li>Panel registry, nginx, <code>apps/{{ site?.domain }}/</code></li>
            <li v-if="site?.runtime === 'node'">Docker service &amp; compose fragment</li>
          </ul>
          <div class="field">
            <label class="label" :for="deleteInputId">
              Type <code>{{ site?.domain }}</code> to confirm
            </label>
            <input
              :id="deleteInputId"
              v-model="deleteConfirm"
              class="input"
              type="text"
              autocomplete="off"
              spellcheck="false"
              :placeholder="site?.domain"
              @keydown.enter="deleteConfirmMatches && confirmDelete()"
            />
          </div>
        </template>
        <p v-else class="alert alert-info">Deletion is running…</p>
        <div class="modal-actions">
          <button v-if="deletePhase === 'confirm'" type="button" class="btn btn-ghost" @click="closeDelete">
            Cancel
          </button>
          <button
            v-if="deletePhase === 'confirm'"
            type="button"
            class="btn btn-danger"
            :disabled="!deleteConfirmMatches"
            @click="confirmDelete"
          >
            Delete permanently
          </button>
          <button v-else type="button" class="btn btn-primary" @click="closeDelete">Close</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
type Resources = { cpuLimit: number; memoryMb: number; diskGb: number; appDirBytes?: number | null }
type SiteOpKind = 'update' | 'rebuild'
type NodeModulesMode = 'auto' | 'keep' | 'clean'

const rebuildModeOptions: {
  value: NodeModulesMode
  title: string
  desc: string
  recommended?: boolean
}[] = [
  {
    value: 'auto',
    title: 'Auto',
    desc: 'Keep node_modules when possible; delete and retry only if install fails.',
    recommended: true
  },
  {
    value: 'keep',
    title: 'Keep',
    desc: 'Never delete node_modules — fastest when dependencies rarely change.'
  },
  {
    value: 'clean',
    title: 'Clean',
    desc: 'Always delete node_modules before install — slowest, most reliable.'
  }
]

const route = useRoute()
const domainParam = computed(() => decodeURIComponent(String(route.params.domain || '')))

const { data, pending, error, refresh } = await useFetch<{
  site: Site
  resources: Resources | null
}>(() => `/api/websites/${encodeURIComponent(domainParam.value)}`, {
  watch: [domainParam]
})

const site = computed(() => data.value?.site)
const resources = computed(() => data.value?.resources)
const loadError = computed(() => {
  if (!error.value) return ''
  const e = error.value as { data?: { statusMessage?: string }; statusMessage?: string }
  return e.data?.statusMessage || e.statusMessage || 'Site not found'
})

const limitsSummary = computed(() => {
  const r = resources.value
  if (!r) return '—'
  const parts: string[] = []
  if (r.cpuLimit > 0) parts.push(`${r.cpuLimit} CPU`)
  if (r.memoryMb > 0) parts.push(`${r.memoryMb} MB RAM`)
  if (r.diskGb > 0) parts.push(`${r.diskGb} GB disk`)
  return parts.length ? parts.join(' · ') : 'Not set (unlimited)'
})

const comingSoon = [
  { icon: 'shield', title: 'SSL / TLS', desc: 'Origin certificates' },
  { icon: 'folder', title: 'File manager', desc: 'Browse apps folder' },
  { icon: 'clock', title: 'Cron jobs', desc: 'Scheduled tasks' },
  { icon: 'database', title: 'Linked database', desc: 'Attach MariaDB' },
  { icon: 'mail', title: 'Email', desc: 'SMTP / mailboxes' }
]

const busy = ref(false)
const streamOp = ref<SiteOpKind | null>(null)
const envOpen = ref(false)
const logOpen = ref(false)
const routingOpen = ref(false)
const resourcesOpen = ref(false)
const updateOpen = ref(false)
const updateMode = ref<'pull' | 'full'>('pull')
const chainRebuildAfterUpdate = ref(false)
const rebuildOpen = ref(false)
const nodeModulesMode = ref<NodeModulesMode>('auto')
const updateGithubUrl = ref('')
const updateToken = ref('')
const updateSaveToken = ref(false)
const updateGitCheckout = ref(false)
const gitTokenStorage = useGitHubTokenStorage()
const deleteOpen = ref(false)
const deletePhase = ref<'confirm' | 'background'>('confirm')
const deleteConfirm = ref('')
const deleteInputId = `delete-confirm-${Math.random().toString(36).slice(2, 9)}`
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

const deleteConfirmMatches = computed(() => {
  const expected = site.value?.domain?.trim().toLowerCase() || ''
  return expected.length > 0 && deleteConfirm.value.trim().toLowerCase() === expected
})

function formatDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US')
}

function fillUpdateForm() {
  const domain = site.value?.domain || domainParam.value
  updateGithubUrl.value = site.value?.githubUrl || ''
  updateSaveToken.value = gitTokenStorage.getSavePreference(domain)
  updateToken.value = gitTokenStorage.getSavedToken(domain)
  updateGitCheckout.value = false
}

function openUpdate() {
  updateMode.value = 'pull'
  updateOpen.value = true
  fillUpdateForm()
  clearAlert()
}

function openFullUpdate() {
  if (!site.value || site.value.runtime !== 'node') return
  updateMode.value = 'full'
  nodeModulesMode.value = 'auto'
  updateOpen.value = true
  fillUpdateForm()
  clearAlert()
}

function closeUpdateModal() {
  updateOpen.value = false
  chainRebuildAfterUpdate.value = false
}

async function confirmUpdate() {
  if (!site.value) return
  clearAlert()
  const url = updateGithubUrl.value.trim()
  if (!url) {
    showAlert('Repository URL is required', false)
    return
  }
  const token = updateToken.value.trim()
  gitTokenStorage.persist(site.value.domain, token, updateSaveToken.value)
  const chainRebuild = updateMode.value === 'full'
  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.value.domain)}/update`, {
      method: 'POST',
      body: {
        githubUrl: url,
        githubToken: token || undefined,
        gitDiscardLocal: updateGitCheckout.value
      }
    })
    updateOpen.value = false
    chainRebuildAfterUpdate.value = chainRebuild
    busy.value = true
    streamOp.value = 'update'
    await refresh()
  } catch (e: unknown) {
    chainRebuildAfterUpdate.value = false
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not start pull', false)
  }
}

function openRebuild() {
  if (!site.value || site.value.runtime !== 'node') return
  nodeModulesMode.value = 'auto'
  rebuildOpen.value = true
  clearAlert()
}

async function confirmRebuild() {
  if (!site.value || site.value.runtime !== 'node') return
  rebuildOpen.value = false
  clearAlert()

  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.value.domain)}/rebuild`, {
      method: 'POST',
      body: { nodeModulesMode: nodeModulesMode.value },
    })
    busy.value = true
    streamOp.value = 'rebuild'
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not start rebuild', false)
  }
}

function onStreamClose() {
  busy.value = false
  streamOp.value = null
  chainRebuildAfterUpdate.value = false
}

async function onStreamDone(payload: { ok: boolean; message: string }) {
  if (payload.ok && chainRebuildAfterUpdate.value && streamOp.value === 'update' && site.value) {
    chainRebuildAfterUpdate.value = false
    try {
      await $fetch(`/api/websites/${encodeURIComponent(site.value.domain)}/rebuild`, {
        method: 'POST',
        body: { nodeModulesMode: nodeModulesMode.value },
      })
      busy.value = true
      streamOp.value = 'rebuild'
      return
    } catch (e: unknown) {
      busy.value = false
      streamOp.value = null
      const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
      showAlert(
        err.data?.statusMessage || err.statusMessage || 'Pull succeeded but could not start rebuild',
        false
      )
      return
    }
  }

  busy.value = false
  chainRebuildAfterUpdate.value = false
  if (payload.ok) streamOp.value = null
  showAlert(payload.message, payload.ok)
}

function onEnvSaved(payload: { restarted: boolean }) {
  envOpen.value = false
  showAlert(
    payload.restarted ? '.env saved and app restarted' : '.env saved — restart or Rebuild to apply',
    true
  )
}

function onRoutingSaved() {
  routingOpen.value = false
  showAlert('Public domains saved (nginx reloaded)', true)
}

async function onResourcesSaved() {
  resourcesOpen.value = false
  await refresh()
  showAlert('Resource limits saved and container updated', true)
}

function openDelete() {
  deleteOpen.value = true
  deletePhase.value = 'confirm'
  deleteConfirm.value = ''
  clearAlert()
}

function closeDelete() {
  deleteOpen.value = false
  deletePhase.value = 'confirm'
  deleteConfirm.value = ''
}

function confirmDelete() {
  if (!site.value || deletePhase.value !== 'confirm' || !deleteConfirmMatches.value) return
  const domain = site.value.domain
  deletePhase.value = 'background'
  void $fetch(`/api/websites/${encodeURIComponent(domain)}`, { method: 'DELETE' })
    .then(() => {
      showAlert(`Deleting ${domain}…`, true)
      setTimeout(() => navigateTo('/websites'), 2500)
    })
    .catch((e: unknown) => {
      const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
      showAlert(err.data?.statusMessage || err.statusMessage || 'Delete failed', false)
      deletePhase.value = 'confirm'
    })
}
</script>

<style scoped>
.breadcrumb {
  margin-bottom: 1rem;
}
.crumb-link {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.88rem;
  color: var(--muted);
  text-decoration: none;
}
.crumb-link:hover {
  color: var(--accent);
}
.site-header {
  padding: 1.25rem 1.35rem;
  margin-bottom: 1.25rem;
}
.site-header-main {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  flex-wrap: wrap;
  margin-bottom: 1rem;
}
.site-header h1 {
  font-size: 1.45rem;
  word-break: break-word;
}
.meta-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem 2rem;
  font-size: 0.88rem;
}
.meta-grid > div {
  min-width: 0;
  max-width: min(100%, 22rem);
}
.meta-grid dt {
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--muted);
  margin-bottom: 0.15rem;
}
.meta-ellipsis {
  display: block;
  color: inherit;
  text-decoration: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.meta-ellipsis:hover {
  color: var(--accent);
  text-decoration: underline;
}
.section {
  margin-bottom: 2rem;
}
.section-title {
  font-size: 0.95rem;
  margin-bottom: 0.75rem;
  color: var(--text);
}
.section-intro {
  font-size: 0.85rem;
  color: var(--muted);
  margin: -0.35rem 0 0.75rem;
}
.tile-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 0.75rem;
}
.tile {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 0.35rem;
  padding: 1rem 1.1rem;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text);
  text-align: left;
  cursor: pointer;
  transition: border-color 0.15s, box-shadow 0.15s, background 0.15s;
  position: relative;
}
button.tile:disabled {
  opacity: 0.55;
  cursor: not-allowed;
}
button.tile:hover:not(:disabled) {
  border-color: var(--accent);
  box-shadow: var(--shadow-sm);
  background: var(--surface-elevated);
}
.tile--muted {
  cursor: default;
  opacity: 0.75;
}
.tile--soon {
  cursor: default;
  opacity: 0.65;
}
.tile-title {
  font-weight: 600;
  font-size: 0.92rem;
}
.tile-desc {
  font-size: 0.78rem;
  color: var(--muted);
  line-height: 1.35;
}
.soon-badge {
  position: absolute;
  top: 0.65rem;
  right: 0.65rem;
  font-size: 0.62rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.15rem 0.4rem;
  border-radius: 4px;
  background: var(--border);
  color: var(--muted);
}
.section--danger {
  padding-top: 1.5rem;
  margin-top: 0.5rem;
  border-top: 1px solid var(--border);
  text-align: right;
}
.btn-delete-quiet {
  padding: 0;
  border: none;
  background: none;
  font-size: 0.85rem;
  color: var(--muted);
  cursor: pointer;
  text-decoration: underline;
  text-underline-offset: 2px;
}
.btn-delete-quiet:hover:not(:disabled) {
  color: var(--danger);
}
.btn-delete-quiet:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.modal .field {
  margin-top: 1rem;
}
.update-options {
  margin-top: 0.75rem;
}
.update-options .checkbox-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 500;
  font-size: 0.88rem;
  cursor: pointer;
  margin-top: 0.65rem;
}
.update-options .checkbox-label:first-of-type {
  margin-top: 0;
}
.update-options .checkbox-label input {
  width: auto;
}
.update-options .hint {
  margin: 0.25rem 0 0 1.55rem;
  font-size: 0.78rem;
  color: var(--muted);
  line-height: 1.4;
}
.modal .field code {
  font-size: 0.85em;
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
.rebuild-modal {
  max-width: 440px;
}
.rebuild-intro {
  margin: 0 0 0.25rem;
  font-size: 0.88rem;
  line-height: 1.45;
}
.rebuild-mode-group {
  margin: 1rem 0 0;
  padding: 0;
  border: none;
  min-width: 0;
}
.rebuild-mode-group .label {
  margin-bottom: 0.5rem;
}
.rebuild-mode-option {
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
  margin-top: 0.5rem;
  padding: 0.75rem 0.85rem;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--surface);
  cursor: pointer;
  transition:
    border-color 0.15s,
    background 0.15s,
    box-shadow 0.15s;
}
.rebuild-mode-option:first-of-type {
  margin-top: 0;
}
.rebuild-mode-option:hover {
  border-color: color-mix(in srgb, var(--accent) 45%, var(--border));
  background: var(--surface-elevated);
}
.rebuild-mode-option--active {
  border-color: var(--accent);
  background: color-mix(in srgb, var(--accent) 8%, var(--surface));
  box-shadow: 0 0 0 1px color-mix(in srgb, var(--accent) 25%, transparent);
}
.rebuild-mode-input {
  flex-shrink: 0;
  margin: 0.2rem 0 0;
  width: 1rem;
  height: 1rem;
  accent-color: var(--accent);
}
.rebuild-mode-body {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  min-width: 0;
}
.rebuild-mode-title {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.4rem;
  font-weight: 600;
  font-size: 0.9rem;
  color: var(--text);
}
.rebuild-mode-badge {
  font-size: 0.62rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.12rem 0.4rem;
  border-radius: 4px;
  background: color-mix(in srgb, var(--accent) 18%, transparent);
  color: var(--accent);
}
.rebuild-mode-desc {
  font-size: 0.8rem;
  line-height: 1.4;
  color: var(--muted);
}
.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}
.delete-list {
  margin: 0.75rem 0;
  padding-left: 1.2rem;
  font-size: 0.88rem;
}
.muted {
  color: var(--muted);
  font-size: 0.88rem;
  margin-bottom: 0.75rem;
}
</style>
