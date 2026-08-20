<template>
  <div>
    <h1>ClamAV</h1>
    <p class="page-desc">
      Scan website files under <code>apps/</code> for known malware. Daemon runs on the VPS host.
      First install may require a signature download (freshclam).
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <PageLoader v-if="loading && !scanBusy" label="Loading ClamAV…" />

    <template v-else>
      <div class="card status-card">
        <dl class="status-dl">
          <div>
            <dt>Installed</dt>
            <dd>{{ data?.installed ? 'Yes' : 'No' }}</dd>
          </div>
          <div>
            <dt>Daemon</dt>
            <dd>{{ data?.daemonActive ? 'Active' : data?.installed ? 'Inactive' : '—' }}</dd>
          </div>
          <div>
            <dt>freshclam</dt>
            <dd>{{ data?.freshclamActive ? 'Active' : data?.installed ? 'Inactive' : '—' }}</dd>
          </div>
          <div>
            <dt>Signatures</dt>
            <dd>{{ data?.signatureDate || '—' }}</dd>
          </div>
        </dl>

        <div class="actions">
          <button
            v-if="!data?.installed"
            type="button"
            class="btn btn-primary"
            :disabled="installBusy"
            @click="onInstall"
          >
            {{ installBusy ? 'Installing…' : 'Install ClamAV' }}
          </button>
          <button
            type="button"
            class="btn btn-sm"
            :disabled="!data?.installed || updateBusy"
            @click="onUpdate"
          >
            {{ updateBusy ? 'Updating…' : 'Update signatures' }}
          </button>
          <button
            type="button"
            class="btn btn-primary btn-sm"
            :disabled="!data?.installed || scanBusy"
            @click="onScan()"
          >
            {{ scanBusy ? 'Scanning…' : 'Scan all apps' }}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" :disabled="refreshBusy" @click="load">
            <AppIcon name="refresh" :size="14" />
            Refresh
          </button>
        </div>
      </div>

      <div v-if="scanResult" class="card section">
        <h2 class="section-title">Last scan</h2>
        <p>
          Target: <code>{{ scanResult.scanPath }}</code> —
          <strong>{{ scanResult.infectedCount }}</strong> infected file(s)
        </p>
        <ul v-if="scanResult.infected?.length" class="hits">
          <li v-for="(h, i) in scanResult.infected" :key="i">
            <span v-if="h.domain" class="domain">{{ h.domain }}</span>
            <code>{{ h.relPath || h.path }}</code>
          </li>
        </ul>
        <p v-else class="muted">No infections detected.</p>
      </div>

      <div v-if="sites.length" class="card section">
        <h2 class="section-title">Scan one website</h2>
        <div class="site-scan-row">
          <select v-model="scanDomain" class="input">
            <option value="">Select domain…</option>
            <option v-for="s in sites" :key="s.domain" :value="s.domain">{{ s.domain }}</option>
          </select>
          <button
            type="button"
            class="btn btn-sm"
            :disabled="!scanDomain || scanBusy || !data?.installed"
            @click="onScan(scanDomain)"
          >
            Scan site
          </button>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
type ClamData = {
  installed?: boolean
  daemonActive?: boolean
  freshclamActive?: boolean
  signatureDate?: string | null
}

type ScanResult = {
  scanPath: string
  infectedCount: number
  infected?: { path: string; domain: string | null; relPath: string }[]
}

const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

const { data: sitesData } = useFetch<{ sites?: { domain: string }[] }>('/api/websites')
const sites = computed(() => sitesData.value?.sites ?? [])

const data = ref<ClamData | null>(null)
const loading = ref(true)
const installBusy = ref(false)
const updateBusy = ref(false)
const scanBusy = ref(false)
const refreshBusy = ref(false)
const scanDomain = ref('')
const scanResult = ref<ScanResult | null>(null)

async function load() {
  refreshBusy.value = true
  try {
    data.value = await $fetch<ClamData>('/api/security/clamav')
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Could not load ClamAV', false)
  } finally {
    loading.value = false
    refreshBusy.value = false
  }
}

async function onInstall() {
  if (!confirm('Install ClamAV on this VPS? Signature download may take several minutes.')) return
  installBusy.value = true
  try {
    await $fetch('/api/security/clamav/install', { method: 'POST', timeout: 600_000 })
    showAlert('ClamAV installed', true)
    await load()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Install failed', false)
  } finally {
    installBusy.value = false
  }
}

async function onUpdate() {
  updateBusy.value = true
  try {
    await $fetch('/api/security/clamav/update', { method: 'POST', timeout: 600_000 })
    showAlert('Signature update finished', true)
    await load()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Update failed', false)
  } finally {
    updateBusy.value = false
  }
}

async function onScan(domain?: string) {
  scanBusy.value = true
  try {
    const result = await $fetch<ScanResult>('/api/security/clamav/scan', {
      method: 'POST',
      body: domain ? { domain } : {},
      timeout: 1_800_000
    })
    scanResult.value = result
    if (result.infectedCount > 0) {
      showAlert(`${result.infectedCount} infected file(s) — see Security events`, false)
    } else {
      showAlert('Scan complete — no infections found', true)
    }
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Scan failed', false)
  } finally {
    scanBusy.value = false
  }
}

onMounted(() => void load())
</script>

<style scoped>
.status-card {
  margin-bottom: 1rem;
}

.status-dl {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 0.75rem 1.5rem;
  margin: 0 0 1rem;
}

.status-dl dt {
  font-size: 0.75rem;
  color: var(--muted);
}

.status-dl dd {
  margin: 0;
  font-weight: 600;
}

.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.section {
  margin-bottom: 1rem;
}

.section-title {
  margin: 0 0 0.75rem;
  font-size: 0.9375rem;
}

.hits {
  margin: 0.5rem 0 0;
  padding-left: 1.25rem;
}

.hits li {
  margin: 0.25rem 0;
}

.domain {
  font-weight: 600;
  margin-right: 0.5rem;
}

.site-scan-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
}

.site-scan-row .input {
  min-width: 220px;
}

.muted {
  color: var(--muted);
}
</style>
