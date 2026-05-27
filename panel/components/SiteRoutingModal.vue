<template>
  <div v-if="open" class="routing-backdrop" @click.self="onCancel">
    <div class="routing-modal card" role="dialog" aria-labelledby="routing-title">
      <header class="routing-header">
        <h2 id="routing-title">Wildcard</h2>
        <p class="routing-sub">
          DNS for store subdomains on this website. Custom merchant domains are managed inside your app, not here.
        </p>
      </header>

      <PageLoader v-if="loading" label="Loading…" />
      <template v-else>
        <p v-if="loadError" class="alert alert-error">{{ loadError }}</p>
        <template v-else>
          <div class="field">
            <span class="label">Website domain</span>
            <div class="domain-readonly" aria-readonly="true">{{ domain }}</div>
            <p class="hint">Set when this site was created in dpanel — cannot be changed here.</p>
            <table class="dns-table" aria-label="Admin site DNS">
              <thead>
                <tr>
                  <th>Type</th>
                  <th>Name</th>
                  <th>Content</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td><code>A</code></td>
                  <td><code>{{ adminDnsName }}</code></td>
                  <td><code>{{ dnsTargetIp }}</code> <span class="muted-inline">(Proxied)</span></td>
                </tr>
              </tbody>
            </table>
          </div>

          <section class="block">
            <h3 class="block-title">Store subdomains (wildcard)</h3>
            <p class="block-desc">
              For multi-store apps: each shop uses <code>shopname.&lt;base&gt;</code>.
              Enter the shared base domain (e.g. <code>dutabi.com</code>, without <code>www</code>).
            </p>
            <label class="label" for="wildcard-base">Base domain</label>
            <input
              id="wildcard-base"
              v-model="wildcardBase"
              class="input"
              type="text"
              placeholder="e.g. dutabi.com"
              :disabled="saving"
              autocomplete="off"
            />
            <template v-if="wildcardBase.trim()">
              <p class="dns-label">Add these records in Cloudflare (zone for the base domain):</p>
              <table class="dns-table" aria-label="Wildcard DNS records">
                <thead>
                  <tr>
                    <th>Type</th>
                    <th>Name</th>
                    <th>Content</th>
                    <th>Opens</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="row in wildcardDnsRows" :key="row.name">
                    <td><code>{{ row.type }}</code></td>
                    <td><code>{{ row.name }}</code></td>
                    <td><code>{{ dnsTargetIp }}</code> <span class="muted-inline">(Proxied)</span></td>
                    <td class="opens-cell">{{ row.opens }}</td>
                  </tr>
                </tbody>
              </table>
            </template>
            <p v-else class="hint">Leave empty if this site does not use shared store subdomains.</p>
          </section>
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
          {{ saving ? 'Applying…' : 'Save & reload nginx' }}
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
const loading = ref(false)
const saving = ref(false)
const loadError = ref('')
const serverIp = ref('')

const adminDnsName = computed(() => {
  const parts = props.domain.toLowerCase().split('.')
  if (parts.length <= 2) return '@'
  return parts[0]!
})

const wildcardDnsRows = computed(() => {
  const base = wildcardBase.value.trim().toLowerCase()
  if (!base) return []
  return [
    { type: 'A', name: '@', opens: `${base}, www.${base}` },
    { type: 'A', name: '*', opens: `*.${base} (e.g. shop.${base})` },
  ]
})

const dnsTargetIp = computed(() => serverIp.value || 'Your VPS IP')

async function loadRouting() {
  loading.value = true
  loadError.value = ''
  wildcardBase.value = ''
  serverIp.value = ''
  try {
    const res = await $fetch<{
      routing?: { wildcardBase?: string }
      serverIp?: string
    }>(`/api/websites/${encodeURIComponent(props.domain)}/routing`)
    wildcardBase.value = res.routing?.wildcardBase ?? ''
    serverIp.value = String(res.serverIp || '').trim()
  } catch (e: unknown) {
    const err = e as { data?: { statusMessage?: string }; statusMessage?: string }
    loadError.value = err.data?.statusMessage || err.statusMessage || 'Could not load wildcard settings'
  } finally {
    loading.value = false
  }
}

async function onSave() {
  saving.value = true
  try {
    await $fetch(`/api/websites/${encodeURIComponent(props.domain)}/routing`, {
      method: 'PUT',
      body: { wildcardBase: wildcardBase.value.trim() }
    })
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
  width: min(580px, 100%);
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
  line-height: 1.45;
}

.domain-readonly {
  padding: 0.5rem 0.65rem;
  border-radius: 6px;
  border: 1px solid var(--border, #e2e8f0);
  background: var(--surface-2, #f1f5f9);
  color: var(--muted, #64748b);
  font-family: ui-monospace, monospace;
  font-size: 0.9rem;
  cursor: not-allowed;
  user-select: all;
}

.block {
  padding: 0.75rem 0 0;
  border-top: 1px solid var(--border, #e2e8f0);
}

.block-title {
  margin: 0 0 0.35rem;
  font-size: 0.95rem;
  font-weight: 600;
}

.block-desc {
  margin: 0 0 0.65rem;
  font-size: 0.82rem;
  color: var(--muted, #64748b);
  line-height: 1.45;
}

.dns-label {
  margin: 0.5rem 0 0.35rem;
  font-size: 0.8rem;
  font-weight: 500;
}

.dns-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.8rem;
  margin: 0.35rem 0;
}

.dns-table th,
.dns-table td {
  padding: 0.4rem 0.5rem;
  text-align: left;
  border: 1px solid var(--border, #e2e8f0);
  vertical-align: top;
}

.dns-table th {
  background: var(--surface-elevated);
  color: var(--text);
  font-weight: 600;
}

.opens-cell {
  font-size: 0.78rem;
  color: var(--muted, #64748b);
}

.muted-inline {
  color: var(--muted, #64748b);
  font-size: 0.78rem;
}

.hint {
  margin: 0.35rem 0 0;
  font-size: 0.78rem;
  color: var(--muted, #64748b);
  line-height: 1.4;
}

.routing-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.5rem;
  padding-top: 0.25rem;
  border-top: 1px solid var(--border, #e2e8f0);
}
</style>
