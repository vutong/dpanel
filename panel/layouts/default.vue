<template>
  <div class="layout">
    <aside v-if="showNav" class="sidebar">
      <div class="brand">dpanel <span v-if="panelVersion" class="ver">v{{ panelVersion }}</span></div>
      <nav>
        <p class="nav-section">Website</p>
        <NuxtLink to="/websites">List Website</NuxtLink>
        <NuxtLink to="/websites/create">Create website</NuxtLink>
        <p class="nav-section">MariaDB</p>
        <NuxtLink to="/databases">List databases</NuxtLink>
        <NuxtLink to="/databases/create">Create database</NuxtLink>
        <NuxtLink to="/databases/phpmyadmin">phpMyAdmin</NuxtLink>
      </nav>
      <button class="btn btn-ghost logout" type="button" @click="logout">Sign out</button>
    </aside>
    <main class="main">
      <slot />
    </main>
  </div>
</template>

<script setup lang="ts">
const route = useRoute()
const showNav = computed(() => route.path !== '/login')

const { data: health } = await useFetch<{ version?: string }>('/api/health', {
  key: 'dpanel-health-version'
})
const panelVersion = computed(() => health.value?.version || '')

async function logout() {
  await $fetch('/api/auth/logout', { method: 'POST' })
  await navigateTo('/login')
}
</script>

<style scoped>
.layout { display: flex; min-height: 100vh; }
.sidebar {
  width: 220px;
  background: var(--surface);
  border-right: 1px solid var(--border);
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
}
.brand { font-size: 1.25rem; font-weight: 700; margin-bottom: 1.5rem; color: var(--accent); }
.brand .ver { font-size: 0.7rem; font-weight: 500; color: var(--muted); }
.nav-section {
  font-size: 0.7rem;
  text-transform: uppercase;
  color: var(--muted);
  margin: 1rem 0 0.4rem;
  letter-spacing: 0.05em;
}
nav a {
  display: block;
  padding: 0.45rem 0.5rem;
  border-radius: 6px;
  color: var(--text);
  text-decoration: none;
  font-size: 0.9rem;
}
nav a:hover, nav a.router-link-active { background: var(--bg); color: var(--accent); }
.logout { margin-top: auto; width: 100%; }
.main { flex: 1; padding: 2rem; max-width: 960px; }
</style>
