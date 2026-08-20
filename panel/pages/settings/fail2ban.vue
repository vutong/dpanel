<template>
  <div>
    <h1>Fail2ban</h1>
    <p class="page-desc">
      Ban IPs after repeated SSH failures, panel login failures, or exploit scans. Runs on the VPS host
      (not inside Docker). See <code>docs/security-ssh.md</code> in the repo.
    </p>

    <PageAlert :message="msg" :success="ok" :alert-key="alertKey" @dismiss="clearAlert" />

    <PageLoader v-if="loading" label="Loading Fail2ban…" />

    <template v-else>
      <div class="card status-card">
        <dl class="status-dl">
          <div>
            <dt>Installed</dt>
            <dd>{{ data?.installed ? 'Yes' : 'No' }}</dd>
          </div>
          <div>
            <dt>Service</dt>
            <dd>{{ data?.active ? 'Active' : data?.installed ? 'Inactive' : '—' }}</dd>
          </div>
          <div>
            <dt>Banned IPs</dt>
            <dd>{{ (data?.bannedIps || []).length }}</dd>
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
            {{ installBusy ? 'Installing…' : 'Install Fail2ban' }}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" :disabled="refreshBusy" @click="load">
            <AppIcon name="refresh" :size="14" />
            Refresh
          </button>
        </div>
      </div>

      <div v-if="data?.jails?.length" class="card section">
        <h2 class="section-title">Jails</h2>
        <table class="table">
          <thead>
            <tr>
              <th>Jail</th>
              <th>Banned IPs</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="j in data.jails" :key="j.name">
              <td><code>{{ j.name }}</code></td>
              <td>
                <span v-if="!j.bannedIps?.length" class="muted">—</span>
                <span v-for="ip in j.bannedIps" v-else :key="ip" class="ip-chip">
                  {{ ip }}
                  <button type="button" class="unban" title="Unban" @click="unban(ip)">×</button>
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="data?.bannedIps?.length" class="card section">
        <h2 class="section-title">All banned IPs</h2>
        <div class="ip-list">
          <span v-for="ip in data.bannedIps" :key="ip" class="ip-chip">
            {{ ip }}
            <button type="button" class="unban" title="Unban" @click="unban(ip)">×</button>
          </span>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
type Fail2banData = {
  ok?: boolean
  installed?: boolean
  active?: boolean
  jails?: { name: string; bannedIps: string[] }[]
  bannedIps?: string[]
}

const { msg, ok, alertKey, clearAlert, showAlert } = usePageAlert()

const data = ref<Fail2banData | null>(null)
const loading = ref(true)
const installBusy = ref(false)
const refreshBusy = ref(false)

async function load() {
  refreshBusy.value = true
  try {
    data.value = await $fetch<Fail2banData>('/api/security/fail2ban')
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Could not load Fail2ban', false)
  } finally {
    loading.value = false
    refreshBusy.value = false
  }
}

async function onInstall() {
  if (!confirm('Install Fail2ban on this VPS?')) return
  installBusy.value = true
  try {
    await $fetch('/api/security/fail2ban/install', { method: 'POST', timeout: 300_000 })
    showAlert('Fail2ban installed', true)
    await load()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Install failed', false)
  } finally {
    installBusy.value = false
  }
}

async function unban(ip: string) {
  if (!confirm(`Unban ${ip}?`)) return
  try {
    await $fetch('/api/security/fail2ban/unban', { method: 'POST', body: { ip } })
    showAlert(`Unbanned ${ip}`, true)
    await load()
  } catch (e: unknown) {
    showAlert(e instanceof Error ? e.message : 'Unban failed', false)
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
  margin-bottom: 0.125rem;
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

.ip-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.ip-chip {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  font-size: 0.8125rem;
  padding: 0.2rem 0.5rem;
  border-radius: 6px;
  background: var(--surface-2);
  font-family: var(--font-mono, monospace);
}

.unban {
  border: none;
  background: transparent;
  color: var(--danger);
  cursor: pointer;
  font-size: 1rem;
  line-height: 1;
  padding: 0 0.15rem;
}

.muted {
  color: var(--muted);
}
</style>
