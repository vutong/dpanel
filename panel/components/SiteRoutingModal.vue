<template>
  <div v-if="open" class="routing-backdrop" @click.self="onCancel">
    <div class="routing-modal card" role="dialog" aria-labelledby="routing-title">
      <header class="routing-header">
        <h2 id="routing-title">Domain routing</h2>
        <p class="routing-sub">
          Public hostnames for <strong>{{ domain }}</strong> (SSL via Cloudflare — nginx serves HTTP only).
        </p>
      </header>

      <PageLoader v-if="loading" label="Loading routing…" />
      <template v-else>
        <p v-if="loadError" class="alert alert-error">{{ loadError }}</p>
        <template v-else>
          <div class="field">
            <label class="label">Primary domain</label>
            <input class="input" type="text" :value="domain" readonly />
            <p class="hint">Always routed to this site container.</p>
          </div>

          <div class="field">
            <label class="label">Wildcard base domain</label>
            <input
              v-model="wildcardBase"
              class="input"
              type="text"
              placeholder="e.g. dutabi.com"
              :disabled="saving"
              autocomplete="off"
            />
            <p class="hint">
              Optional. Also routes <code>www.&lt;base&gt;</code> and <code>*.&lt;base&gt;</code> (store subdomains).
              Point DNS <code>*</code> and apex to this server in Cloudflare.
            </p>
          </div>

          <div class="field">
            <label class="label">Extra domains</label>
            <div class="extra-list">
              <div v-for="(host, idx) in extraDomains" :key="`${host}-${idx}`" class="extra-row">
                <code>{{ host }}</code>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm"
                  :disabled="saving"
                  @click="removeExtra(idx)"
                >
                  Remove
                </button>
              </div>
              <p v-if="!extraDomains.length" class="hint">No extra domains yet (e.g. custom store domains).</p>
            </div>
            <div class="extra-add">
              <input
                v-model="newExtra"
                class="input"
                type="text"
                placeholder="shop-customer.com"
                :disabled="saving"
                autocomplete="off"
                @keydown.enter.prevent="addExtra"
              />
              <button type="button" class="btn btn-ghost" :disabled="saving || !newExtra.trim()" @click="addExtra">
                Add
              </button>
            </div>
          </div>

          <div v-if="serverNames.length" class="preview card-muted">
            <p class="label">Active <code>server_name</code> preview</p>
            <p class="preview-names">{{ serverNames.join(' · ') }}</p>
          </div>
        </template>
      </template>

      <footer class="routing-footer">
        <button type="button" class="btn btn-ghost" :disabled="saving" @click="onCancel">Cancel</button>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="loading || !!loadError || saving"
          @click="onSave"
        >
          {{ saving ? 'Applying…' : 'Save & apply nginx' }}
        </button>
      </footer>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  open: boolean
  domain: string
}>()

const emit = defineEmits<{
  close: []
  saved: []
}>()

const wildcardBase = ref('')
const extraDomains = ref<string[]>([])
const newExtra = ref('')
const serverNames = ref<string[]>([])
const loading = ref(false)
const saving = ref(false)
const loadError = ref('')

async function loadRouting() {
  loading.value = true
  loadError.value = ''
  wildcardBase.value = ''
  extraDomains.value = []
  serverNames.value = []
  try {
    const res = await $fetch<{
      routing?: { wildcardBase?: string; extraDomains?: string[] }
      serverNames?: string[]
    }>(`/api/websites/${encodeURIComponent(props.domain)}/routing`)
    wildcardBase.value = res.routing?.wildcardBase ?? ''
    extraDomains.value = [...(res.routing?.extraDomains ?? [])]
    serverNames.value = res.serverNames ?? []
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Could not load domain routing'
  } finally {
    loading.value = false
  }
}

function addExtra() {
  const host = newExtra.value.trim().toLowerCase()
  if (!host) return
  if (host === props.domain.toLowerCase()) return
  if (!extraDomains.value.includes(host)) extraDomains.value.push(host)
  newExtra.value = ''
}

function removeExtra(idx: number) {
  extraDomains.value.splice(idx, 1)
}

async function onSave() {
  saving.value = true
  try {
    const res = await $fetch<{ serverNames?: string[] }>(
      `/api/websites/${encodeURIComponent(props.domain)}/routing`,
      {
        method: 'PUT',
        body: {
          wildcardBase: wildcardBase.value.trim(),
          extraDomains: extraDomains.value
        }
      }
    )
    serverNames.value = res.serverNames ?? []
    emit('saved')
    emit('close')
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Save failed'
  } finally {
    saving.value = false
  }
}

function onCancel() {
  emit('close')
}

watch(
  () => [props.open, props.domain] as const,
  ([isOpen, d]) => {
    if (isOpen && d) loadRouting()
  }
)
</script>

<style scoped>
.routing-backdrop {
  position: fixed;
  inset: 0;
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
  background: rgba(15, 23, 42, 0.45);
}

.routing-modal {
  width: min(560px, 100%);
  max-height: 90vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.routing-header h2 {
  margin: 0 0 0.35rem;
  font-size: 1.15rem;
}

.routing-sub {
  margin: 0;
  font-size: 0.85rem;
  color: var(--muted, #64748b);
}

.extra-list {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  margin-bottom: 0.5rem;
}

.extra-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.35rem 0.5rem;
  border-radius: 6px;
  background: var(--surface-2, #f1f5f9);
}

.extra-add {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.extra-add .input {
  flex: 1;
}

.btn-sm {
  padding: 0.2rem 0.5rem;
  font-size: 0.75rem;
}

.preview {
  padding: 0.65rem 0.75rem;
  border-radius: 8px;
  font-size: 0.8rem;
}

.preview-names {
  margin: 0.35rem 0 0;
  word-break: break-word;
  line-height: 1.45;
}

.routing-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  padding-top: 0.25rem;
  border-top: 1px solid var(--border, #e2e8f0);
}
</style>
