<template>
  <div class="scan-panel card">
    <h2 class="section-title">Run scan</h2>
    <p class="muted intro">
      Scans files under <code>apps/</code> on the VPS host. Full-tree scans are CPU/RAM heavy — prefer
      per-site scans on small VPS.
    </p>

    <div v-if="scanLocked" class="alert alert-warn lock-banner">
      <strong>Scan in progress</strong>
      — {{ lockLabel }}
      <span v-if="polling" class="muted"> (refreshing every few seconds)</span>
    </div>

    <div class="actions">
      <button
        type="button"
        class="btn btn-primary"
        :disabled="!installed || scanLocked || scanBusy"
        @click="emit('scan-all')"
      >
        {{ scanBusy && !scanDomain ? 'Starting…' : 'Scan all apps' }}
      </button>
    </div>

    <div v-if="sites.length" class="site-row">
      <select v-model="scanDomain" class="select" :disabled="!installed || scanLocked">
        <option value="">Select website…</option>
        <option v-for="s in sites" :key="s.domain" :value="s.domain">{{ s.domain }}</option>
      </select>
      <button
        type="button"
        class="btn btn-ghost btn-sm"
        :disabled="!scanDomain || !installed || scanLocked || scanBusy"
        @click="emit('scan-site', scanDomain)"
      >
        Scan site
      </button>
    </div>
    <p v-else class="muted empty">No websites yet — create one to scan per site.</p>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  installed: boolean
  sites: { domain: string }[]
  scanLocked: boolean
  scanBusy: boolean
  polling: boolean
  activeTarget?: string | null
}>()

const emit = defineEmits<{
  'scan-all': []
  'scan-site': [domain: string]
}>()

const scanDomain = ref('')

const lockLabel = computed(() => {
  const t = props.activeTarget
  if (!t || t === 'all') return 'Scanning all apps…'
  return `Scanning ${t}…`
})
</script>

<style scoped>
.section-title {
  margin: 0 0 0.5rem;
  font-size: 0.9375rem;
}

.intro {
  margin: 0 0 1rem;
  font-size: 0.875rem;
  line-height: 1.5;
}

.lock-banner {
  margin-bottom: 1rem;
  font-size: 0.875rem;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.site-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
}

.site-row .input {
  min-width: 220px;
}

.muted {
  color: var(--muted);
}

.empty {
  margin: 0;
  font-size: 0.875rem;
}
</style>
