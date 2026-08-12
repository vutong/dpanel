<template>
  <div class="fm">
    <nav class="breadcrumb">
      <NuxtLink to="/websites" class="crumb-link">Websites</NuxtLink>
      <span class="crumb-sep">/</span>
      <NuxtLink :to="`/websites/${encodeURIComponent(domainParam)}`" class="crumb-link">
        {{ domainParam }}
      </NuxtLink>
      <span class="crumb-sep">/</span>
      <span class="crumb-current">Files</span>
    </nav>

    <PageLoader v-if="pending && !listing" label="Loading files…" />
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else-if="listing">
      <header class="fm-head">
        <div>
          <h1>File manager</h1>
          <p class="fm-sub">
            <code>apps/{{ listing.domain }}/</code>
            <span v-if="diskLabel" class="disk">{{ diskLabel }}</span>
          </p>
        </div>
        <div class="fm-actions">
          <input
            ref="fileInput"
            type="file"
            class="sr-only"
            multiple
            :disabled="readOnly"
            @change="onFilePick"
          />
          <button type="button" class="btn btn-ghost btn-sm" :disabled="busy" @click="refresh()">
            <AppIcon name="refresh" :size="16" />
            Refresh
          </button>
          <button type="button" class="btn btn-ghost btn-sm" :disabled="readOnly || busy" @click="openMkdir">
            <AppIcon name="folder-plus" :size="16" />
            New folder
          </button>
          <button type="button" class="btn btn-primary btn-sm" :disabled="readOnly || busy" @click="fileInput?.click()">
            <AppIcon name="upload" :size="16" />
            Upload
          </button>
        </div>
      </header>

      <div v-if="listing.pendingDelete" class="alert alert-info">
        This site is pending delete — browse and download only. Restore the site to upload or edit files.
      </div>
      <div v-else-if="listing.isPanel" class="alert alert-info">
        This is the panel site. Deleting <code>.output</code> or <code>node_modules</code> is blocked (it would stop
        dpanel).
      </div>
      <div v-if="opRunning" class="alert alert-info">
        A Git pull or Rebuild is running. Changing files now can race the job — wait until it finishes if you can.
      </div>
      <div v-if="listing.runtime === 'php' && !listing.hasPublicDir" class="alert alert-info">
        Nginx document root is <code>apps/{{ listing.domain }}/public</code>. Create a <code>public</code> folder or PHP
        will not serve this site.
      </div>
      <p v-if="listing.hasGithub" class="fm-warn">
        Update from Git (especially with discard local changes) overwrites files uploaded here.
        <template v-if="listing.runtime === 'node'"> Node sites may need a Rebuild after changing runtime files.</template>
      </p>
      <div v-if="listing.truncated" class="alert alert-info">
        Listing truncated at 2000 entries. Avoid browsing <code>node_modules</code> / <code>.git</code>.
      </div>

      <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

      <nav class="path-bar" aria-label="Path">
        <button type="button" class="path-seg" :class="{ active: !cwd }" @click="goPath('')">
          {{ listing.domain }}
        </button>
        <template v-for="(seg, i) in pathSegs" :key="`${i}-${seg}`">
          <span class="crumb-sep">/</span>
          <button
            type="button"
            class="path-seg"
            :class="{ active: i === pathSegs.length - 1 }"
            @click="goPath(pathSegs.slice(0, i + 1).join('/'))"
          >
            {{ seg }}
          </button>
        </template>
      </nav>

      <div
        class="card table-wrap"
        :class="{ 'is-drag': dragOver }"
        @dragenter.prevent="onDragEnter"
        @dragover.prevent="onDragOver"
        @dragleave="onDragLeave"
        @drop.prevent="onDrop"
      >
        <div v-if="dragOver && !readOnly" class="drop-hint">Drop files to upload into this folder</div>
        <div v-if="selected.size" class="bulk-bar">
          <span>{{ selected.size }} selected</span>
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            :disabled="busy || selectedFileCount !== 1"
            @click="downloadSelected"
          >
            Download
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            :disabled="readOnly || busy || selected.size !== 1"
            @click="openRename"
          >
            Rename
          </button>
          <button type="button" class="btn btn-danger btn-sm" :disabled="readOnly || busy" @click="openDelete">
            Delete
          </button>
        </div>
        <table class="table">
          <thead>
            <tr>
              <th class="col-check">
                <input
                  type="checkbox"
                  :checked="allVisibleSelected"
                  :disabled="!listing.entries.length"
                  @change="toggleAll"
                />
              </th>
              <th>Name</th>
              <th class="col-size">Size</th>
              <th class="col-mtime">Modified</th>
              <th class="col-actions">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="cwd">
              <td></td>
              <td colspan="4">
                <button type="button" class="name-btn up" @click="goUp">
                  <AppIcon name="folder" :size="16" />
                  ..
                </button>
              </td>
            </tr>
            <tr v-if="!listing.entries.length">
              <td colspan="5" class="empty">This folder is empty.</td>
            </tr>
            <tr
              v-for="e in listing.entries"
              :key="e.name"
              :class="{ 'row-heavy': e.heavy, 'row-escaped': e.escaped }"
            >
              <td class="col-check">
                <input type="checkbox" :checked="selected.has(e.name)" @change="toggleOne(e.name)" />
              </td>
              <td>
                <button type="button" class="name-btn" @click="onOpen(e)">
                  <AppIcon :name="e.type === 'dir' ? 'folder' : 'file'" :size="16" />
                  <span class="name-text">{{ e.name }}</span>
                  <span v-if="e.symlink" class="tag">link</span>
                  <span v-if="e.escaped" class="tag tag-warn">outside</span>
                  <span v-if="e.heavy" class="tag">large</span>
                </button>
              </td>
              <td class="col-size muted">{{ e.type === 'dir' ? '—' : formatBytes(e.size) }}</td>
              <td class="col-mtime muted">{{ formatDate(e.mtime) }}</td>
              <td class="col-actions">
                <div class="action-row">
                  <IconButton
                    v-if="e.type === 'file' && !e.escaped"
                    icon="download"
                    title="Download"
                    :disabled="busy"
                    @click="downloadRel(joinRel(cwd, e.name), e.name)"
                  />
                  <IconButton
                    icon="edit"
                    title="Rename"
                    :disabled="readOnly || busy || e.escaped"
                    @click="openRenameOne(e.name)"
                  />
                  <IconButton
                    icon="trash"
                    title="Delete"
                    variant="danger"
                    :disabled="readOnly || busy"
                    @click="openDeleteOne(e.name)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <div v-if="mkdirOpen" class="modal-backdrop" @click.self="mkdirOpen = false">
      <div class="modal card" role="dialog" aria-modal="true">
        <h2>New folder</h2>
        <label class="label" for="fm-mkdir">Name</label>
        <input id="fm-mkdir" v-model="mkdirName" class="input" @keyup.enter="confirmMkdir" />
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="mkdirOpen = false">Cancel</button>
          <button type="button" class="btn btn-primary" :disabled="busy || !mkdirName.trim()" @click="confirmMkdir">
            Create
          </button>
        </div>
      </div>
    </div>

    <div v-if="renameOpen" class="modal-backdrop" @click.self="renameOpen = false">
      <div class="modal card" role="dialog" aria-modal="true">
        <h2>Rename</h2>
        <label class="label" for="fm-rename">New name</label>
        <input id="fm-rename" v-model="renameTo" class="input" @keyup.enter="confirmRename" />
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="renameOpen = false">Cancel</button>
          <button type="button" class="btn btn-primary" :disabled="busy || !renameTo.trim()" @click="confirmRename">
            Rename
          </button>
        </div>
      </div>
    </div>

    <div v-if="deleteOpen" class="modal-backdrop" @click.self="deleteOpen = false">
      <div class="modal card" role="dialog" aria-modal="true">
        <h2>Delete</h2>
        <p class="muted">This cannot be undone.</p>
        <ul class="delete-list">
          <li v-for="n in deleteNames" :key="n">
            {{ n }}
            <span v-if="isSensitive(n)" class="tag tag-warn">sensitive</span>
          </li>
        </ul>
        <p v-if="deleteHasSensitive" class="alert alert-error">
          One or more names are critical (public, .env, package.json, .output, …).
        </p>
        <div v-if="deleteNeedsType" class="field">
          <label class="label" for="fm-del">
            Type <code>{{ deleteTypeTarget }}</code> to confirm
          </label>
          <input id="fm-del" v-model="deleteTyped" class="input" autocomplete="off" />
        </div>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="deleteOpen = false">Cancel</button>
          <button
            type="button"
            class="btn btn-danger"
            :disabled="busy || (deleteNeedsType && !deleteTypedOk)"
            @click="confirmDelete"
          >
            Delete
          </button>
        </div>
      </div>
    </div>

    <div v-if="previewOpen" class="modal-backdrop" @click.self="closePreview">
      <div class="modal card preview-modal" role="dialog" aria-modal="true">
        <div class="preview-head">
          <h2>{{ previewName }}</h2>
          <button type="button" class="btn btn-ghost btn-sm" @click="closePreview">
            <AppIcon name="x" :size="16" />
          </button>
        </div>
        <PageLoader v-if="previewKind === 'loading'" label="Loading preview…" />
        <p v-else-if="previewKind === 'error'" class="alert alert-error">{{ previewError }}</p>
        <img
          v-else-if="previewKind === 'image' && previewImageUrl"
          :src="previewImageUrl"
          :alt="previewName"
          class="preview-img"
        />
        <pre v-else-if="previewKind === 'text'" class="preview-text">{{ previewText }}</pre>
        <p v-if="previewTruncated" class="muted">Preview truncated — download the full file.</p>
        <div class="modal-actions">
          <button type="button" class="btn btn-ghost" @click="closePreview">Close</button>
          <button type="button" class="btn btn-primary" @click="downloadRel(previewRel, previewName)">Download</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { formatBytes } from '~/composables/useFormatBytes'

type FileEntry = {
  name: string
  type: 'file' | 'dir'
  size: number | null
  mtime: string | null
  mode: string
  symlink: boolean
  escaped: boolean
  heavy: boolean
}

type Listing = {
  ok: boolean
  domain: string
  runtime: string
  path: string
  pendingDelete: boolean
  isPanel: boolean
  hasPublicDir: boolean
  hasGithub: boolean
  truncated: boolean
  entries: FileEntry[]
  disk: { usedBytes: number | null; limitBytes: number; freeHostBytes: number | null }
}

const SENSITIVE = new Set([
  '.env',
  '.git',
  '.output',
  'node_modules',
  'package.json',
  'composer.json',
  'wp-config.php',
  'public',
  'vendor'
])

const route = useRoute()
const router = useRouter()
const domainParam = computed(() => decodeURIComponent(String(route.params.domain || '')))
const cwd = computed(() => String(route.query.path || '').replace(/^\/+|\/+$/g, ''))

const apiBase = computed(() => `/api/websites/${encodeURIComponent(domainParam.value)}/files`)

const { data, pending, error, refresh } = await useFetch<Listing>(
  () => `${apiBase.value}?path=${encodeURIComponent(cwd.value)}`,
  { watch: [domainParam, cwd] }
)

const listing = computed(() => data.value)
const loadError = computed(() => {
  if (!error.value) return ''
  const e = error.value as { data?: { statusMessage?: string }; statusMessage?: string }
  return e.data?.statusMessage || e.statusMessage || 'Cannot list files'
})

const { data: opData } = await useFetch<{ status?: string }>(
  () => `/api/websites/${encodeURIComponent(domainParam.value)}/operation`,
  { watch: [domainParam] }
)
const opRunning = computed(() => opData.value?.status === 'running')

const readOnly = computed(() => !!listing.value?.pendingDelete)
const pathSegs = computed(() => (cwd.value ? cwd.value.split('/').filter(Boolean) : []))
const diskLabel = computed(() => {
  const d = listing.value?.disk
  if (!d) return ''
  const used = formatBytes(d.usedBytes)
  if (d.limitBytes > 0) return `${used} / ${formatBytes(d.limitBytes)}`
  return used !== '—' ? used : ''
})

const fileInput = ref<HTMLInputElement | null>(null)
const selected = ref(new Set<string>())
const busy = ref(false)
const dragOver = ref(false)
const dragDepth = ref(0)
const mkdirOpen = ref(false)
const mkdirName = ref('')
const renameOpen = ref(false)
const renameFrom = ref('')
const renameTo = ref('')
const deleteOpen = ref(false)
const deleteNames = ref<string[]>([])
const deleteTyped = ref('')
const previewOpen = ref(false)
const previewKind = ref<'loading' | 'text' | 'image' | 'error'>('loading')
const previewName = ref('')
const previewRel = ref('')
const previewText = ref('')
const previewImageUrl = ref('')
const previewError = ref('')
const previewTruncated = ref(false)
const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

watch(cwd, () => {
  selected.value = new Set()
})

const allVisibleSelected = computed(() => {
  const entries = listing.value?.entries || []
  return entries.length > 0 && entries.every((e) => selected.value.has(e.name))
})

const selectedFileCount = computed(() => {
  const entries = listing.value?.entries || []
  return [...selected.value].filter((n) => entries.find((e) => e.name === n)?.type === 'file').length
})

const deleteHasSensitive = computed(() => deleteNames.value.some((n) => SENSITIVE.has(n)))
const deleteDirNames = computed(() => {
  const entries = listing.value?.entries || []
  return deleteNames.value.filter((n) => entries.find((e) => e.name === n)?.type === 'dir')
})
const deleteNeedsType = computed(() => deleteDirNames.value.length > 0 || deleteHasSensitive.value)
const deleteTypeTarget = computed(() => {
  if (deleteDirNames.value.length === 1 && deleteNames.value.length === 1) return deleteDirNames.value[0]
  return 'DELETE'
})
const deleteTypedOk = computed(
  () => deleteTyped.value.trim().toLowerCase() === deleteTypeTarget.value.toLowerCase()
)

function isSensitive(name: string) {
  return SENSITIVE.has(name)
}

function joinRel(dir: string, name: string) {
  return dir ? `${dir}/${name}` : name
}

function apiErr(e: unknown) {
  const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
  return err.data?.statusMessage || err.statusMessage || 'Request failed'
}

function formatDate(iso?: string | null) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('en-US')
}

function goPath(path: string) {
  router.replace({ query: path ? { path } : {} })
}

function goUp() {
  const parts = pathSegs.value.slice(0, -1)
  goPath(parts.join('/'))
}

function toggleOne(name: string) {
  const next = new Set(selected.value)
  if (next.has(name)) next.delete(name)
  else next.add(name)
  selected.value = next
}

function toggleAll(ev: Event) {
  const on = (ev.target as HTMLInputElement).checked
  selected.value = on ? new Set((listing.value?.entries || []).map((e) => e.name)) : new Set()
}

async function onOpen(e: FileEntry) {
  if (e.escaped) {
    showAlert('Symlink target is outside the site directory', false)
    return
  }
  if (e.type === 'dir') {
    goPath(joinRel(cwd.value, e.name))
    return
  }
  await openPreview(e)
}

async function openPreview(e: FileEntry) {
  closePreview()
  previewOpen.value = true
  previewKind.value = 'loading'
  previewName.value = e.name
  previewRel.value = joinRel(cwd.value, e.name)
  previewText.value = ''
  previewTruncated.value = false
  try {
    const res = await fetch(
      `${apiBase.value}/preview?path=${encodeURIComponent(previewRel.value)}`,
      { credentials: 'same-origin' }
    )
    const ct = res.headers.get('content-type') || ''
    if (!res.ok) {
      let message = 'Preview failed'
      try {
        const body = (await res.json()) as { statusMessage?: string }
        if (body.statusMessage) message = body.statusMessage
      } catch {
        /* ignore */
      }
      throw new Error(message)
    }
    if (ct.startsWith('image/')) {
      const blob = await res.blob()
      previewKind.value = 'image'
      previewImageUrl.value = URL.createObjectURL(blob)
      return
    }
    const data = (await res.json()) as { content?: string; truncated?: boolean }
    previewKind.value = 'text'
    previewText.value = data.content || ''
    previewTruncated.value = !!data.truncated
  } catch (err: unknown) {
    previewKind.value = 'error'
    previewError.value = err instanceof Error ? err.message : 'Preview failed'
  }
}

function closePreview() {
  previewOpen.value = false
  if (previewImageUrl.value) {
    URL.revokeObjectURL(previewImageUrl.value)
    previewImageUrl.value = ''
  }
}

async function downloadRel(rel: string, name: string) {
  try {
    const res = await fetch(`${apiBase.value}/download?path=${encodeURIComponent(rel)}`, {
      credentials: 'same-origin'
    })
    if (!res.ok) {
      let message = 'Download failed'
      try {
        const body = (await res.json()) as { statusMessage?: string }
        if (body.statusMessage) message = body.statusMessage
      } catch {
        /* ignore */
      }
      throw new Error(message)
    }
    const blob = await res.blob()
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = name
    a.click()
    URL.revokeObjectURL(url)
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Download failed', false)
  }
}

function downloadSelected() {
  const name = [...selected.value][0]
  if (!name) return
  downloadRel(joinRel(cwd.value, name), name)
}

function openMkdir() {
  mkdirName.value = ''
  mkdirOpen.value = true
}

async function confirmMkdir() {
  const name = mkdirName.value.trim()
  if (!name || name.includes('/') || name.includes('\\') || name === '.' || name === '..') {
    showAlert('Invalid folder name', false)
    return
  }
  busy.value = true
  clearAlert()
  try {
    await $fetch(`${apiBase.value}/mkdir`, { method: 'POST', body: { path: joinRel(cwd.value, name) } })
    mkdirOpen.value = false
    showAlert(`Created ${name}`, true)
    await refresh()
  } catch (e: unknown) {
    showAlert(apiErr(e), false)
  } finally {
    busy.value = false
  }
}

function openRenameOne(name: string) {
  selected.value = new Set([name])
  openRename()
}

function openRename() {
  const name = [...selected.value][0]
  if (!name) return
  renameFrom.value = name
  renameTo.value = name
  renameOpen.value = true
}

async function confirmRename() {
  const toName = renameTo.value.trim()
  if (!toName || !renameFrom.value) return
  if (toName.includes('/') || toName.includes('\\') || toName === '.' || toName === '..') {
    showAlert('Invalid name', false)
    return
  }
  busy.value = true
  clearAlert()
  try {
    await $fetch(`${apiBase.value}/rename`, {
      method: 'POST',
      body: { from: joinRel(cwd.value, renameFrom.value), to: joinRel(cwd.value, toName) }
    })
    renameOpen.value = false
    selected.value = new Set()
    showAlert(`Renamed to ${toName}`, true)
    await refresh()
  } catch (e: unknown) {
    showAlert(apiErr(e), false)
  } finally {
    busy.value = false
  }
}

function openDeleteOne(name: string) {
  selected.value = new Set([name])
  openDelete()
}

function openDelete() {
  deleteNames.value = [...selected.value]
  deleteTyped.value = ''
  if (!deleteNames.value.length) return
  deleteOpen.value = true
}

async function confirmDelete() {
  if (deleteNeedsType.value && !deleteTypedOk.value) return
  busy.value = true
  clearAlert()
  try {
    await $fetch(`${apiBase.value}/delete`, {
      method: 'POST',
      body: { paths: deleteNames.value.map((n) => joinRel(cwd.value, n)) }
    })
    deleteOpen.value = false
    selected.value = new Set()
    showAlert('Deleted', true)
    await refresh()
  } catch (e: unknown) {
    showAlert(apiErr(e), false)
  } finally {
    busy.value = false
  }
}

async function uploadFiles(files: FileList | File[]) {
  const list = [...files]
  if (!list.length || readOnly.value) return
  busy.value = true
  clearAlert()
  try {
    const form = new FormData()
    form.set('path', cwd.value)
    for (const f of list) form.append('file', f, f.name)
    await $fetch(`${apiBase.value}/upload`, { method: 'POST', body: form })
    const n = list.length
    showAlert(n === 1 ? `Uploaded ${list[0].name}` : `Uploaded ${n} files`, true)
    await refresh()
  } catch (e: unknown) {
    showAlert(apiErr(e), false)
  } finally {
    busy.value = false
    if (fileInput.value) fileInput.value.value = ''
  }
}

function onFilePick(ev: Event) {
  const input = ev.target as HTMLInputElement
  if (input.files?.length) uploadFiles(input.files)
}

function onDragEnter() {
  dragDepth.value += 1
  dragOver.value = true
}

function onDragOver() {
  dragOver.value = true
}

function onDragLeave() {
  dragDepth.value = Math.max(0, dragDepth.value - 1)
  if (dragDepth.value === 0) dragOver.value = false
}

function onDrop(ev: DragEvent) {
  dragDepth.value = 0
  dragOver.value = false
  const files = ev.dataTransfer?.files
  if (files?.length) uploadFiles(files)
}
</script>

<style scoped>
.breadcrumb {
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.35rem;
  font-size: 0.88rem;
}
.crumb-link {
  color: var(--muted);
  text-decoration: none;
}
.crumb-link:hover {
  color: var(--accent);
}
.crumb-sep {
  color: var(--muted);
  opacity: 0.6;
}
.crumb-current {
  color: var(--text);
  font-weight: 600;
}
.fm-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 1rem;
  flex-wrap: wrap;
  margin-bottom: 1rem;
}
.fm-sub {
  margin-top: 0.35rem;
  color: var(--muted);
  font-size: 0.85rem;
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: center;
}
.fm-sub .disk {
  color: var(--muted);
}
.fm-warn {
  font-size: 0.82rem;
  color: var(--muted);
  margin: -0.35rem 0 0.85rem;
  line-height: 1.4;
}
.fm-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}
.path-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.2rem;
  margin: 0.5rem 0 0.85rem;
  font-size: 0.88rem;
}
.path-seg {
  border: none;
  background: none;
  color: var(--accent);
  cursor: pointer;
  padding: 0.15rem 0.25rem;
  border-radius: 4px;
  font-size: inherit;
}
.path-seg:hover {
  background: var(--accent-muted);
}
.path-seg.active {
  color: var(--text);
  font-weight: 600;
  cursor: default;
}
.table-wrap {
  overflow-x: auto;
  padding: 0;
  position: relative;
}
.table-wrap.is-drag {
  outline: 2px dashed var(--accent);
  outline-offset: -2px;
}
.drop-hint {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: color-mix(in srgb, var(--accent) 12%, transparent);
  color: var(--accent);
  font-weight: 600;
  z-index: 2;
  pointer-events: none;
}
.bulk-bar {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
  padding: 0.65rem 0.85rem;
  border-bottom: 1px solid var(--border);
  font-size: 0.85rem;
}
.col-check {
  width: 2.2rem;
}
.col-size,
.col-mtime {
  white-space: nowrap;
}
.col-actions {
  text-align: right;
  white-space: nowrap;
}
.action-row {
  display: inline-flex;
  justify-content: flex-end;
  gap: 0.3rem;
}
.name-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  border: none;
  background: none;
  color: var(--text);
  cursor: pointer;
  font-size: 0.9rem;
  padding: 0.15rem 0;
  max-width: 100%;
}
.name-btn:hover .name-text {
  color: var(--accent);
  text-decoration: underline;
}
.name-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.name-btn.up {
  color: var(--muted);
}
.tag {
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.1rem 0.35rem;
  border-radius: 4px;
  background: var(--border);
  color: var(--muted);
  flex-shrink: 0;
}
.tag-warn {
  background: var(--danger-muted);
  color: var(--danger);
}
.empty {
  color: var(--muted);
  text-align: center;
  padding: 1.5rem 0.85rem;
}
.row-escaped {
  opacity: 0.7;
}
.muted {
  color: var(--muted);
  font-size: 0.88rem;
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
.preview-modal {
  max-width: min(920px, 100%);
  max-height: 90vh;
  overflow: auto;
}
.preview-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}
.preview-head h2 {
  font-size: 1rem;
  word-break: break-all;
}
.preview-img {
  display: block;
  max-width: 100%;
  max-height: 60vh;
  margin: 0 auto;
  border-radius: 8px;
}
.preview-text {
  max-height: 55vh;
  overflow: auto;
  padding: 0.85rem;
  border-radius: 8px;
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  font-size: 0.8rem;
  line-height: 1.45;
  white-space: pre-wrap;
  word-break: break-word;
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
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  border: 0;
}
</style>
