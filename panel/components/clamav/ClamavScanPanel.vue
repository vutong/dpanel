<template>
  <div class="scan-panel card">
    <header class="panel-head">
      <h2 class="section-title">Run scan</h2>
      <p class="muted intro">
        Scans files under <code>apps/</code> on the VPS host. Prefer a single site on small VPS —
        full-tree scans are CPU/RAM heavy.
      </p>
    </header>

    <div v-if="scanLocked" class="progress-row" role="status">
      <span class="progress-dot" aria-hidden="true" />
      <div class="progress-text">
        <strong>{{ lockLabel }}</strong>
        <span class="muted">Open the scan dialog for live status, or check Results when finished.</span>
      </div>
    </div>

    <div class="scan-grid" :class="{ 'scan-grid--locked': scanLocked }">
      <section class="scan-block">
        <h3 class="block-title">All apps</h3>
        <p class="block-desc muted">Scan every website under <code>apps/</code>.</p>
        <button
          type="button"
          class="btn btn-primary"
          :disabled="!installed || scanLocked"
          @click="emit('open-scan', null)"
        >
          Scan all apps…
        </button>
      </section>

      <section class="scan-block">
        <h3 class="block-title">One website</h3>
        <p class="block-desc muted">Scan a single site directory only.</p>
        <template v-if="sites.length">
          <div class="site-row">
            <select
              v-model="scanDomain"
              class="select"
              :disabled="!installed || scanLocked"
              aria-label="Website to scan"
            >
              <option value="">Select website…</option>
              <option v-for="s in sites" :key="s.domain" :value="s.domain">{{ s.domain }}</option>
            </select>
            <button
              type="button"
              class="btn btn-primary"
              :disabled="!scanDomain || !installed || scanLocked"
              @click="emit('open-scan', scanDomain)"
            >
              Scan site…
            </button>
          </div>
        </template>
        <p v-else class="muted empty">No websites yet — create one to scan per site.</p>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  installed: boolean
  sites: { domain: string }[]
  scanLocked: boolean
  activeTarget?: string | null
}>()

const emit = defineEmits<{
  'open-scan': [domain: string | null]
}>()

const scanDomain = ref('')

const lockLabel = computed(() => {
  const t = props.activeTarget
  if (!t || t === 'all') return 'Scanning all apps…'
  return `Scanning ${t}…`
})
</script>

<style scoped>
.panel-head {
  margin-bottom: 1rem;
}

.section-title {
  margin: 0 0 0.35rem;
  font-size: 0.9375rem;
}

.intro {
  margin: 0;
  font-size: 0.875rem;
  line-height: 1.5;
}

.progress-row {
  display: flex;
  align-items: flex-start;
  gap: 0.65rem;
  margin-bottom: 1rem;
  padding: 0.75rem 0.9rem;
  border-radius: 8px;
  border: 1px solid color-mix(in srgb, var(--accent) 30%, var(--border));
  background: var(--bg-subtle);
}

.progress-dot {
  width: 0.55rem;
  height: 0.55rem;
  margin-top: 0.35rem;
  border-radius: 50%;
  background: var(--accent);
  flex-shrink: 0;
  animation: pulse 1.2s ease-in-out infinite;
}

.progress-text {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
  min-width: 0;
}

.progress-text strong {
  font-size: 0.875rem;
}

.progress-text .muted {
  font-size: 0.8125rem;
}

.scan-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 1rem;
}

.scan-grid--locked {
  opacity: 0.72;
}

.scan-block {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 1rem;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--surface-elevated);
}

.block-title {
  margin: 0;
  font-size: 0.875rem;
  font-weight: 600;
}

.block-desc {
  margin: 0;
  font-size: 0.8125rem;
  line-height: 1.4;
  flex: 1;
}

.site-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
}

.site-row .select {
  flex: 1 1 180px;
  min-width: 0;
}

.muted {
  color: var(--muted);
}

.empty {
  margin: 0;
  font-size: 0.8125rem;
}

@keyframes pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
}
</style>
