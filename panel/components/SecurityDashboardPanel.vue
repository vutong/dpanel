<template>
  <aside class="host-metrics security-metrics" aria-label="Security" :aria-busy="pending">
    <h3 class="metrics-title">Security</h3>

    <template v-if="pending">
      <div class="svc-list" aria-hidden="true">
        <div v-for="n in 2" :key="n" class="svc-row">
          <span class="skeleton skeleton-text" style="width: 4.5rem" />
          <span class="skeleton skeleton-text" style="width: 3.25rem" />
        </div>
      </div>
      <div class="f2b-stats skel-f2b" aria-hidden="true">
        <div v-for="n in 3" :key="n">
          <span class="skeleton skeleton-line-sm" style="width: 2.5rem; margin-bottom: 0.35rem" />
          <span class="skeleton skeleton-text-lg" style="width: 1.75rem" />
        </div>
      </div>
    </template>

    <template v-else>
      <div class="svc-list">
        <div class="svc-row">
          <NuxtLink to="/settings/clamav" class="svc-name">ClamAV</NuxtLink>
          <span v-if="clamOk" class="status-active">Active</span>
          <span v-else class="status-inactive">{{ clamLabel }}</span>
        </div>
        <div class="svc-row">
          <NuxtLink to="/settings/fail2ban" class="svc-name">Fail2ban</NuxtLink>
          <span v-if="fail2banOk" class="status-active">Active</span>
          <span v-else class="status-inactive">{{ fail2banLabel }}</span>
        </div>
      </div>

      <dl class="f2b-stats">
        <div>
          <dt>Jail(s)</dt>
          <dd>
            <template v-if="fail2banPending && !fail2ban">
              <span class="skeleton skeleton-text" style="width: 1.5rem" aria-hidden="true" />
            </template>
            <template v-else>{{ jailCount }}</template>
          </dd>
        </div>
        <div>
          <dt>Banned</dt>
          <dd>
            <template v-if="fail2banPending && !fail2ban">
              <span class="skeleton skeleton-text" style="width: 1.5rem" aria-hidden="true" />
            </template>
            <template v-else>{{ bannedCount }}</template>
          </dd>
        </div>
        <div>
          <dt>Suspected</dt>
          <dd>
            <template v-if="fail2banPending && !fail2ban">
              <span class="skeleton skeleton-text" style="width: 1.5rem" aria-hidden="true" />
            </template>
            <template v-else>{{ suspectedCount }}</template>
          </dd>
        </div>
      </dl>

      <p v-if="!installedAny" class="hint muted">
        Not installed yet — open Fail2ban or ClamAV to set up.
      </p>
    </template>
  </aside>
</template>

<script setup lang="ts">
type Status = {
  fail2ban?: { installed?: boolean; active?: boolean }
  clamav?: { installed?: boolean; daemonActive?: boolean }
}

type Fail2banSummary = {
  jails?: { currentlyFailed?: number }[]
  bannedIps?: string[]
}

const REFRESH_MS = 60_000

const { data: status, pending: statusPending } = useFetch<Status>('/api/security/status', {
  key: 'security-status-dashboard',
  refreshInterval: REFRESH_MS
})

const { data: fail2ban, pending: fail2banPending } = useFetch<Fail2banSummary>(
  '/api/security/fail2ban',
  {
    key: 'security-fail2ban-dashboard',
    refreshInterval: REFRESH_MS
  }
)

/** Full block skeleton until status arrives; counts can fill later. */
const pending = computed(() => statusPending.value && !status.value)

const fail2banOk = computed(
  () => status.value?.fail2ban?.installed && status.value?.fail2ban?.active
)
const clamOk = computed(
  () => status.value?.clamav?.installed && status.value?.clamav?.daemonActive
)
const installedAny = computed(
  () => status.value?.fail2ban?.installed || status.value?.clamav?.installed
)

const fail2banLabel = computed(() => {
  if (!status.value?.fail2ban?.installed) return 'Not installed'
  return status.value.fail2ban.active ? 'Active' : 'Inactive'
})
const clamLabel = computed(() => {
  if (!status.value?.clamav?.installed) return 'Not installed'
  return status.value.clamav.daemonActive ? 'Active' : 'Inactive'
})

const jailCount = computed(() => fail2ban.value?.jails?.length ?? 0)
const bannedCount = computed(() => fail2ban.value?.bannedIps?.length ?? 0)
const suspectedCount = computed(() =>
  (fail2ban.value?.jails || []).reduce((n, j) => n + (j.currentlyFailed || 0), 0)
)
</script>

<style scoped>
.host-metrics {
  background: var(--bg-subtle);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 1rem 1rem 0.85rem;
}

.metrics-title {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--muted);
  margin: 0 0 0.85rem;
  font-weight: 600;
}

.svc-list {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
}

.svc-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
}

.svc-name {
  font-size: 0.78rem;
  font-weight: 600;
  color: var(--text);
  text-decoration: none;
}

.svc-name:hover {
  color: var(--accent);
}

.f2b-stats {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 0.5rem;
  margin: 0.85rem 0 0;
  padding-top: 0.75rem;
  border-top: 1px solid var(--border);
}

.skel-f2b {
  align-items: start;
}

.f2b-stats dt {
  font-size: 0.65rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--muted);
  margin-bottom: 0.15rem;
  font-weight: 600;
}

.f2b-stats dd {
  margin: 0;
  font-size: 0.9rem;
  font-weight: 700;
  color: var(--text);
  font-variant-numeric: tabular-nums;
  min-height: 1.25em;
  display: flex;
  align-items: center;
}

.hint {
  margin: 0.75rem 0 0;
  font-size: 0.75rem;
  line-height: 1.4;
}
</style>
