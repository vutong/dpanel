<template>
  <div class="jail-form">
    <div v-if="sshdWarning" class="alert alert-warn sshd-banner">
      <strong>SSH jail warning:</strong>
      Keep an open SSH session while changing <code>sshd</code> settings. Add your office IP to
      <em>ignoreip</em> first. Increase limits gradually to avoid locking yourself out.
    </div>

    <div class="card section">
      <h2 class="section-title">Global whitelist (ignoreip)</h2>
      <p class="hint muted">
        IPs or CIDR ranges never banned. One per line or comma-separated.
      </p>
      <textarea
        v-model="ignoreipText"
        class="input textarea"
        rows="3"
        placeholder="127.0.0.1/8&#10;::1&#10;203.0.113.10"
      />
      <div v-if="clientIp" class="client-ip-row">
        <span class="muted">Your current IP (panel): <code>{{ clientIp }}</code></span>
        <button type="button" class="btn btn-ghost btn-sm" @click="addClientIp">
          Add to whitelist
        </button>
      </div>
    </div>

    <div v-for="jail in jailList" :key="jail.name" class="card section jail-card">
      <div class="jail-head">
        <h2 class="section-title">
          <code>{{ jail.name }}</code>
          <span class="badge" :class="jail.managedBy === 'dpanel' ? 'badge-dpanel' : 'badge-system'">
            {{ jail.managedBy }}
          </span>
        </h2>
        <button type="button" class="btn btn-ghost btn-sm" @click="emit('reset-jail', jail.name)">
          Reset to default
        </button>
      </div>

      <dl v-if="jail.filter || jail.logpath" class="meta-dl muted">
        <template v-if="jail.filter">
          <dt>Filter</dt>
          <dd><code>{{ jail.filter }}</code></dd>
        </template>
        <template v-if="jail.logpath">
          <dt>Log</dt>
          <dd><code>{{ jail.logpath }}</code></dd>
        </template>
        <template v-if="installed">
          <dt>Currently failed</dt>
          <dd>{{ jail.currentlyFailed ?? 0 }}</dd>
        </template>
      </dl>

      <div v-if="draft.jails[jail.name]" class="fields-grid">
        <label class="toggle-row">
          <input v-model="draft.jails[jail.name].enabled" type="checkbox" />
          Enabled
        </label>
        <label>
          <span class="label-sm">maxretry</span>
          <input
            v-model.number="draft.jails[jail.name].maxretry"
            type="number"
            min="1"
            max="20"
            class="input"
          />
        </label>
        <label>
          <span class="label-sm">findtime (sec)</span>
          <input
            v-model.number="draft.jails[jail.name].findtime"
            type="number"
            min="60"
            max="86400"
            class="input"
          />
        </label>
        <label>
          <span class="label-sm">bantime (sec)</span>
          <input
            v-model.number="draft.jails[jail.name].bantime"
            type="number"
            min="60"
            max="86400"
            class="input"
          />
        </label>
      </div>
    </div>

    <div class="save-row">
      <button type="button" class="btn btn-primary" :disabled="saving || applying" @click="openConfirm">
        {{ saving || applying ? 'Saving…' : 'Save settings' }}
      </button>
      <p v-if="formFeedback" class="form-feedback" :class="formFeedbackOk ? 'ok' : 'err'">
        {{ formFeedback }}
      </p>
    </div>

    <Teleport to="body">
      <div v-if="confirmOpen" class="modal-backdrop" @click.self="closeConfirm">
        <div class="modal card" role="dialog" aria-modal="true">
          <h2>Apply Fail2ban settings?</h2>
          <p class="muted">This writes config on the VPS host and reloads Fail2ban.</p>
          <ul v-if="changeSummary.length" class="changes">
            <li v-for="(c, i) in changeSummary" :key="i">{{ c }}</li>
          </ul>
          <p v-else class="muted changes-empty">No changes detected — settings will be re-applied as-is.</p>
          <label v-if="hasSshdChanges" class="confirm-check">
            <input v-model="sshConfirm" type="checkbox" />
            I have an open SSH session
          </label>
          <p v-if="applyBlocked" class="apply-blocked">
            Tick the SSH confirmation above to apply <code>sshd</code> changes.
          </p>
          <p v-if="modalError" class="modal-error">{{ modalError }}</p>
          <div class="modal-actions">
            <button type="button" class="btn btn-ghost" :disabled="applying" @click="closeConfirm">
              Cancel
            </button>
            <button
              type="button"
              class="btn btn-primary"
              :disabled="applying || applyBlocked"
              @click="confirmSave"
            >
              {{ applying ? 'Applying…' : 'Apply' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<script setup lang="ts">
type JailSettings = {
  enabled: boolean
  maxretry: number
  findtime: number
  bantime: number
}

type JailDetail = {
  name: string
  managedBy: 'dpanel' | 'system'
  filter?: string | null
  logpath?: string | null
  currentlyFailed?: number
  enabled?: boolean
  maxretry?: number
  findtime?: number
  bantime?: number
}

type Settings = {
  ignoreip: string[]
  jails: Record<string, JailSettings>
}

type SaveResult = { ok: boolean; message: string }

const props = defineProps<{
  settings: Settings
  jails: JailDetail[]
  installed: boolean
  clientIp?: string | null
  saving?: boolean
  onSave: (settings: Settings) => Promise<SaveResult>
}>()

const emit = defineEmits<{ 'reset-jail': [string] }>()

const draft = reactive<{ ignoreip: string[]; jails: Record<string, JailSettings> }>({
  ignoreip: [],
  jails: {}
})

const ignoreipText = computed({
  get: () => draft.ignoreip.join('\n'),
  set: (v: string) => {
    draft.ignoreip = v
      .split(/[\n,]+/)
      .map((s) => s.trim())
      .filter(Boolean)
  }
})

const confirmOpen = ref(false)
const sshConfirm = ref(false)
const applying = ref(false)
const modalError = ref('')
const formFeedback = ref('')
const formFeedbackOk = ref(true)

function syncDraft(from: Settings) {
  if (confirmOpen.value || applying.value) return
  draft.ignoreip = [...(from.ignoreip || [])]
  draft.jails = {}
  const names = new Set<string>()
  for (const j of props.jails) names.add(j.name)
  for (const name of Object.keys(from.jails || {})) names.add(name)
  for (const name of names) {
    const live = props.jails.find((j) => j.name === name)
    const saved = from.jails[name]
    draft.jails[name] = {
      enabled: saved?.enabled ?? live?.enabled ?? true,
      maxretry: Number(saved?.maxretry ?? live?.maxretry ?? 5),
      findtime: Number(saved?.findtime ?? live?.findtime ?? 600),
      bantime: Number(saved?.bantime ?? live?.bantime ?? 3600)
    }
  }
}

watch(
  () => props.settings,
  (s) => syncDraft(s),
  { immediate: true, deep: true }
)

watch(
  () => props.jails,
  () => syncDraft(props.settings),
  { deep: true }
)

const jailList = computed(() => {
  const fromLive = props.jails || []
  const names = new Set(fromLive.map((j) => j.name))
  for (const name of Object.keys(draft.jails)) names.add(name)
  return [...names].sort().map((name) => {
    const live = fromLive.find((j) => j.name === name)
    return (
      live || {
        name,
        managedBy: (name === 'nginx-dpanel-login' || name === 'nginx-php-exploit'
          ? 'dpanel'
          : 'system') as 'dpanel' | 'system'
      }
    )
  }) as JailDetail[]
})

const sshdWarning = computed(() => jailList.value.some((j) => j.name === 'sshd'))

function jailChanged(name: string, prev: JailSettings | undefined, cur: JailSettings | undefined): boolean {
  if (!prev || !cur) return false
  return (
    Boolean(prev.enabled) !== Boolean(cur.enabled) ||
    Number(prev.maxretry) !== Number(cur.maxretry) ||
    Number(prev.findtime) !== Number(cur.findtime) ||
    Number(prev.bantime) !== Number(cur.bantime)
  )
}

const hasSshdChanges = computed(() =>
  jailChanged('sshd', props.settings.jails.sshd, draft.jails.sshd)
)

const applyBlocked = computed(() => hasSshdChanges.value && !sshConfirm.value)

const changeSummary = computed(() => {
  const lines: string[] = []
  const origIp = (props.settings.ignoreip || []).join(', ')
  const newIp = draft.ignoreip.join(', ')
  if (origIp !== newIp) lines.push(`ignoreip: ${newIp || '(empty)'}`)
  for (const [name, cfg] of Object.entries(draft.jails)) {
    const prev = props.settings.jails[name]
    if (!prev) {
      lines.push(`${name}: new jail settings`)
      continue
    }
    if (jailChanged(name, prev, cfg)) {
      lines.push(
        `${name}: enabled=${cfg.enabled}, maxretry=${cfg.maxretry}, findtime=${cfg.findtime}, bantime=${cfg.bantime}`
      )
    }
  }
  return lines
})

function addClientIp() {
  if (!props.clientIp) return
  if (!draft.ignoreip.includes(props.clientIp)) {
    draft.ignoreip.push(props.clientIp)
  }
}

function cloneJails(jails: Record<string, JailSettings>): Record<string, JailSettings> {
  const out: Record<string, JailSettings> = {}
  for (const [name, cfg] of Object.entries(jails)) {
    out[name] = {
      enabled: Boolean(cfg.enabled),
      maxretry: Number(cfg.maxretry),
      findtime: Number(cfg.findtime),
      bantime: Number(cfg.bantime)
    }
  }
  return out
}

function buildPayload(): Settings {
  return {
    ignoreip: [...draft.ignoreip],
    jails: cloneJails(draft.jails)
  }
}

function openConfirm() {
  formFeedback.value = ''
  modalError.value = ''
  sshConfirm.value = false
  confirmOpen.value = true
}

function closeConfirm() {
  if (applying.value) return
  confirmOpen.value = false
  modalError.value = ''
}

async function confirmSave() {
  if (applyBlocked.value || applying.value) return
  modalError.value = ''
  applying.value = true
  try {
    const result = await props.onSave(buildPayload())
    if (result.ok) {
      formFeedbackOk.value = true
      formFeedback.value = result.message
      applying.value = false
      confirmOpen.value = false
      modalError.value = ''
    } else {
      modalError.value = result.message
    }
  } catch (e: unknown) {
    modalError.value = e instanceof Error ? e.message : 'Apply failed'
  } finally {
    applying.value = false
  }
}
</script>

<style scoped>
.section {
  margin-bottom: 1rem;
}

.section-title {
  margin: 0;
  font-size: 0.9375rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
}

.jail-head {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 0.75rem;
  margin-bottom: 0.75rem;
}

.badge {
  font-size: 0.6875rem;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  font-weight: 600;
  text-transform: uppercase;
}

.badge-dpanel {
  background: color-mix(in srgb, var(--accent) 15%, transparent);
  color: var(--accent);
}

.badge-system {
  background: var(--surface-2);
  color: var(--muted);
}

.meta-dl {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0.25rem 0.75rem;
  font-size: 0.8125rem;
  margin: 0 0 0.75rem;
}

.meta-dl dt {
  margin: 0;
}

.meta-dl dd {
  margin: 0;
  word-break: break-all;
}

.fields-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 0.75rem;
}

.label-sm {
  display: block;
  font-size: 0.75rem;
  color: var(--muted);
  margin-bottom: 0.25rem;
}

.toggle-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.875rem;
  padding-top: 1.25rem;
}

.textarea {
  width: 100%;
  font-family: var(--font-mono, monospace);
  font-size: 0.8125rem;
}

.hint {
  font-size: 0.8125rem;
  margin: 0 0 0.5rem;
}

.client-ip-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
  margin-top: 0.5rem;
  font-size: 0.8125rem;
}

.sshd-banner {
  margin-bottom: 1rem;
  font-size: 0.875rem;
}

.save-row {
  margin-top: 0.5rem;
}

.form-feedback {
  margin: 0.75rem 0 0;
  font-size: 0.875rem;
}

.form-feedback.ok {
  color: var(--success, #16a34a);
}

.form-feedback.err {
  color: var(--danger);
}

.changes {
  margin: 0.75rem 0;
  padding-left: 1.25rem;
  font-size: 0.8125rem;
}

.changes-empty {
  font-size: 0.8125rem;
  margin: 0.75rem 0 0;
}

.confirm-check {
  display: flex;
  gap: 0.5rem;
  align-items: center;
  font-size: 0.875rem;
  margin: 0.75rem 0 0;
}

.apply-blocked {
  margin: 0.5rem 0 0;
  font-size: 0.8125rem;
  color: var(--warning, #ca8a04);
}

.modal-error {
  margin: 0.75rem 0 0;
  font-size: 0.875rem;
  color: var(--danger);
}

.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2000;
  padding: 1rem;
}

.modal {
  max-width: 480px;
  width: 100%;
}

.modal h2 {
  margin: 0 0 0.5rem;
  font-size: 1rem;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  margin-top: 1rem;
}

.muted {
  color: var(--muted);
}
</style>
