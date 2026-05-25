<template>
  <div>
    <h1>Dashboard</h1>
    <p class="muted">Manage websites and MariaDB on this VPS.</p>
    <div class="grid">
      <NuxtLink to="/websites" class="card link-card">
        <h2>Websites</h2>
        <p>{{ siteCount }} site(s)</p>
      </NuxtLink>
      <NuxtLink to="/databases" class="card link-card">
        <h2>MariaDB</h2>
        <p>{{ dbCount }} database(s)</p>
      </NuxtLink>
    </div>
  </div>
</template>

<script setup lang="ts">
const { data: sites } = await useFetch('/api/websites')
const { data: dbs } = await useFetch('/api/databases')
const siteCount = computed(() => sites.value?.sites?.length ?? 0)
const dbCount = computed(() => dbs.value?.databases?.length ?? 0)
</script>

<style scoped>
.muted { color: var(--muted); margin: 0.5rem 0 1.5rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; }
.link-card { text-decoration: none; color: inherit; transition: border-color 0.15s; }
.link-card:hover { border-color: var(--accent); }
h2 { font-size: 1.1rem; margin-bottom: 0.35rem; }
</style>
