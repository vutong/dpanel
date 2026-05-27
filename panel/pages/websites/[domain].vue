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
        <div class="site-header-top">
          <div class="site-header-main">
            <h1>{{ site.domain }}</h1>
            <span :class="site.runtime === 'node' ? 'badge badge-node' : 'badge badge-php'">
              {{ site.runtime }}
            </span>
          </div>
          <div v-if="site.githubUrl" class="github-block">
            <span class="meta-label">GitHub</span>
            <a
              :href="site.githubUrl"
              class="github-url"
              target="_blank"
              rel="noopener noreferrer"
              :title="site.githubUrl"
            >{{ site.githubUrl }}</a>
          </div>
        </div>
        <dl class="meta-grid">
          <div>
            <dt>Created</dt>
            <dd>{{ formatDate(site.createdAt) }}</dd>
          </div>
          <div v-if="site.runtime === 'node' && resources">
            <dt>Limits</dt>
            <dd>{{ limitsSummary }}</dd>
          </div>
        </dl>
      </header>

      <PageAlert :message="msg" :success="ok" :alert-key="alertKey" />

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
            @click="runRebuild"
          >
            <AppIcon name="wrench" :size="22" />
            <span class="tile-title">Rebuild</span>
            <span class="tile-desc">npm install &amp; build</span>
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
            <span class="tile-title">Public domains</span>
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
          <button type="button" class="tile" :disabled="busy || routingSyncing" @click="runRoutingSync">
            <AppIcon name="globe" :size="22" />
            <span class="tile-title">Sync custom domains</span>
            <span class="tile-desc">MongoDB → nginx (add &amp; remove)</span>
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
        <h2 class="section-title">Danger zone</h2>
        <button type="button" class="btn btn-danger" :disabled="busy" @click="openDelete">
          Delete website
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

    <div v-if="updateOpen" class="modal-backdrop" @click.self="updateOpen = false">
      <div class="modal card" role="dialog">
        <h2>Update from Git</h2>
        <p class="muted">Pull latest code for <strong>{{ site?.domain }}</strong></p>
        <div class="field">
          <label class="label">GitHub token (PAT)</label>
          <input v-model="updateToken" class="input" type="password" autocomplete="off" />
        </div>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="updateOpen = false">Cancel</button>
          <button type="button" class="btn btn-primary" @click="confirmUpdate">Pull from Git</button>
        </div>
      </div>
    </div>

    <div v-if="deleteOpen" class="modal-backdrop" @click.self="closeDelete">
      <div class="modal card" role="dialog">
        <h2>Delete website</h2>
        <p class="muted">Remove <strong>{{ site?.domain }}</strong> permanently.</p>
        <ul v-if="deletePhase === 'confirm'" class="delete-list">
          <li>Panel registry, nginx, <code>apps/{{ site?.domain }}/</code></li>
          <li v-if="site?.runtime === 'node'">Docker service &amp; compose fragment</li>
        </ul>
        <p v-else class="alert alert-info">Deletion is running…</p>
        <div class="modal-actions">
          <button v-if="deletePhase === 'confirm'" type="button" class="btn btn-ghost" @click="closeDelete">
            Cancel
          </button>
          <button
            v-if="deletePhase === 'confirm'"
            type="button"
            class="btn btn-danger"
            @click="confirmDelete"
          >
            Delete
          </button>
          <button v-else type="button" class="btn btn-primary" @click="closeDelete">Close</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { formatBytes } from '~/composables/useFormatBytes'

type Site = { domain: string; runtime: string; githubUrl?: string; createdAt?: string }
type Resources = { cpuLimit: number; memoryMb: number; diskGb: number; appDirBytes?: number | null }
type SiteOpKind = 'update' | 'rebuild'

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
  if (r.appDirBytes) parts.push(`using ${formatBytes(r.appDirBytes)}`)
  return parts.length ? parts.join(' · ') : 'No limits'
})

const comingSoon = [
  { icon: 'shield', title: 'SSL / TLS', desc: 'Origin certificates' },
  { icon: 'folder', title: 'File manager', desc: 'Browse apps folder' },
  { icon: 'clock', title: 'Cron jobs', desc: 'Scheduled tasks' },
  { icon: 'database', title: 'Linked database', desc: 'Attach MariaDB' },
  { icon: 'layers', title: 'Deployments', desc: 'Release history' },
  { icon: 'mail', title: 'Email', desc: 'SMTP / mailboxes' }
]

const busy = ref(false)
const streamOp = ref<SiteOpKind | null>(null)
const envOpen = ref(false)
const logOpen = ref(false)
const routingOpen = ref(false)
const resourcesOpen = ref(false)
const routingSyncing = ref(false)
const updateOpen = ref(false)
const updateToken = ref('')
const deleteOpen = ref(false)
const deletePhase = ref<'confirm' | 'background'>('confirm')
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

function formatDate(iso?: string) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US')
}

function openUpdate() {
  updateOpen.value = true
  updateToken.value = ''
  clearAlert()
}

async function confirmUpdate() {
  if (!site.value) return
  clearAlert()
  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.value.domain)}/update`, {
      method: 'POST',
      body: { githubToken: updateToken.value.trim() || undefined }
    })
    updateOpen.value = false
    busy.value = true
    streamOp.value = 'update'
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Could not start pull', false)
  }
}

async function runRebuild() {
  if (!site.value || site.value.runtime !== 'node') return
  clearAlert()
  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.value.domain)}/rebuild`, { method: 'POST' })
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
}

function onStreamDone(payload: { ok: boolean; message: string }) {
  busy.value = false
  if (payload.ok) streamOp.value = null
  showAlert(payload.message, payload.ok, payload.ok ? 8000 : 0)
}

function onEnvSaved(payload: { restarted: boolean }) {
  envOpen.value = false
  showAlert(
    payload.restarted ? '.env saved and app restarted' : '.env saved — restart or Rebuild to apply',
    true,
    8000
  )
}

function onRoutingSaved() {
  routingOpen.value = false
  showAlert('Public domains saved (nginx reloaded)', true, 8000)
}

async function onResourcesSaved() {
  resourcesOpen.value = false
  await refresh()
  showAlert('Resource limits saved and container updated', true, 8000)
}

async function runRoutingSync() {
  if (!site.value || site.value.runtime !== 'node' || routingSyncing.value) return
  routingSyncing.value = true
  clearAlert()
  try {
    await $fetch(`/api/websites/${encodeURIComponent(site.value.domain)}/routing-sync`, {
      method: 'POST'
    })
    showAlert('Custom domains reconciled with MongoDB (nginx reloaded)', true, 10000)
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    showAlert(err.data?.statusMessage || err.statusMessage || 'Domain sync failed', false)
  } finally {
    routingSyncing.value = false
  }
}

function openDelete() {
  deleteOpen.value = true
  deletePhase.value = 'confirm'
  clearAlert()
}

function closeDelete() {
  deleteOpen.value = false
  deletePhase.value = 'confirm'
}

function confirmDelete() {
  if (!site.value || deletePhase.value !== 'confirm') return
  const domain = site.value.domain
  deletePhase.value = 'background'
  void $fetch(`/api/websites/${encodeURIComponent(domain)}`, { method: 'DELETE' })
    .then(() => {
      showAlert(`Deleting ${domain}…`, true, 4000)
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
.site-header-top {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1.25rem;
  margin-bottom: 1rem;
}
.site-header-main {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  flex-wrap: wrap;
  flex-shrink: 0;
  min-width: 0;
}
.site-header h1 {
  font-size: 1.45rem;
  word-break: break-word;
}
.github-block {
  flex: 1 1 12rem;
  min-width: 0;
  max-width: min(52%, 520px);
  text-align: right;
}
.meta-label {
  display: block;
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--muted);
  margin-bottom: 0.2rem;
}
.github-url {
  display: block;
  font-size: 0.8rem;
  font-family: ui-monospace, monospace;
  color: var(--accent);
  text-decoration: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.github-url:hover {
  text-decoration: underline;
}
.meta-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem 2rem;
  font-size: 0.88rem;
}
.meta-grid dt {
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--muted);
  margin-bottom: 0.15rem;
}
@media (max-width: 640px) {
  .site-header-top {
    flex-direction: column;
    align-items: stretch;
  }
  .github-block {
    max-width: none;
    text-align: left;
  }
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
  padding-top: 0.5rem;
  border-top: 1px solid var(--border);
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
