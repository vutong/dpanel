<template>
  <div>
    <PageLoader v-if="loading" label="Loading overview…" />
    <template v-else>
      <h1>Overview</h1>
      <p class="page-desc">Manage websites and MariaDB on this VPS.</p>
      <div class="grid">
        <NuxtLink to="/websites" class="card stat-card">
          <div class="stat-icon">
            <AppIcon name="globe" :size="22" />
          </div>
          <div>
            <h2>Websites</h2>
            <p class="stat-value">{{ siteCount }} <span class="stat-unit">site(s)</span></p>
          </div>
        </NuxtLink>
        <NuxtLink to="/databases" class="card stat-card">
          <div class="stat-icon stat-icon-db">
            <AppIcon name="database" :size="22" />
          </div>
          <div>
            <h2>MariaDB</h2>
            <p class="stat-value">{{ dbCount }} <span class="stat-unit">database(s)</span></p>
          </div>
        </NuxtLink>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
const { data: sites, pending: sitesPending } = useFetch('/api/websites')
const { data: dbs, pending: dbsPending } = useFetch('/api/databases')
const loading = computed(() => sitesPending.value || dbsPending.value)
const siteCount = computed(() => sites.value?.sites?.length ?? 0)
const dbCount = computed(() => dbs.value?.databases?.length ?? 0)
</script>

<style scoped>
.page-desc {
  color: var(--muted);
  margin: 0.35rem 0 1.75rem;
  font-size: 0.95rem;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: 1rem;
}

.stat-card {
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  text-decoration: none;
  color: inherit;
  transition:
    border-color 0.15s,
    box-shadow 0.15s,
    transform 0.15s;
}

.stat-card:hover {
  border-color: var(--accent);
  box-shadow: var(--shadow-md);
  transform: translateY(-2px);
  text-decoration: none;
}

.stat-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.75rem;
  height: 2.75rem;
  border-radius: 10px;
  background: var(--accent-muted);
  color: var(--accent);
  flex-shrink: 0;
}

.stat-icon-db {
  background: var(--success-muted);
  color: var(--success);
}

.stat-card h2 {
  font-size: 1rem;
  margin-bottom: 0.35rem;
  color: var(--text);
}

.stat-value {
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--text);
}

.stat-unit {
  font-size: 0.85rem;
  font-weight: 500;
  color: var(--muted);
}
</style>
