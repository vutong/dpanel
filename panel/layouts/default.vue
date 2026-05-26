<template>
  <div class="layout">
    <aside v-if="showNav" class="sidebar">
      <NuxtLink to="/" class="brand">
        <AppIcon name="dashboard" :size="22" class="brand-icon" />
        <span class="brand-text">
          dpanel
          <span v-if="panelVersion" class="ver">v{{ panelVersion }}</span>
        </span>
      </NuxtLink>

      <nav class="nav">
        <SidebarNavLink to="/" icon="dashboard" label="Dashboard" :sub="false" />

        <p class="nav-section">
          <AppIcon name="globe" :size="14" class="section-icon" />
          Website
        </p>
        <SidebarNavLink to="/websites" icon="list" label="List Website" />
        <SidebarNavLink to="/websites/create" icon="plus" label="Create website" />

        <p class="nav-section">
          <AppIcon name="database" :size="14" class="section-icon" />
          MariaDB
        </p>
        <SidebarNavLink to="/databases/create" icon="database-plus" label="Create database" />
        <SidebarNavLink to="/databases" icon="database" label="List databases" />
        <SidebarNavLink to="/databases/delete" icon="trash" label="Delete database" />
        <SidebarNavLink to="/databases/phpmyadmin" icon="table" label="phpMyAdmin" />
      </nav>

      <button class="logout-btn" type="button" @click="logout">
        <span class="logout-label">Sign out</span>
        <AppIcon name="log-out" :size="18" class="logout-icon" />
      </button>
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
.layout {
  display: flex;
  min-height: 100vh;
}

.sidebar {
  width: 240px;
  background: var(--surface);
  border-right: 1px solid var(--border);
  padding: 1.25rem 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

.brand {
  display: flex;
  align-items: center;
  gap: 0.65rem;
  margin-bottom: 1.25rem;
  padding: 0.35rem 0.5rem;
  border-radius: 8px;
  text-decoration: none;
  color: var(--accent);
  transition: background 0.15s;
}

.brand:hover {
  background: var(--bg);
  text-decoration: none;
}

.brand-icon {
  color: var(--accent);
}

.brand-text {
  font-size: 1.2rem;
  font-weight: 700;
  line-height: 1.2;
}

.brand .ver {
  display: block;
  font-size: 0.68rem;
  font-weight: 500;
  color: var(--muted);
}

.nav {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.nav-section {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.68rem;
  text-transform: uppercase;
  color: var(--muted);
  margin: 0.85rem 0 0.35rem 0.5rem;
  letter-spacing: 0.06em;
  font-weight: 600;
}

.nav-section:first-of-type {
  margin-top: 0;
}

.section-icon {
  opacity: 0.75;
}

:deep(.nav-link--main),
:deep(.nav-link--sub) {
  display: flex;
  align-items: center;
  text-decoration: none;
  transition: background 0.15s, color 0.15s;
}

:deep(.nav-link--main) {
  gap: 0.65rem;
  padding: 0.5rem 0.65rem;
  margin-bottom: 0.35rem;
  border-radius: 8px;
  color: var(--text);
  font-size: 0.9rem;
  font-weight: 500;
}

:deep(.nav-link--sub) {
  gap: 0.55rem;
  padding: 0.4rem 0.55rem 0.4rem 0.75rem;
  border-radius: 7px;
  color: var(--text);
  font-size: 0.8rem;
}

:deep(.nav-link--main:hover),
:deep(.nav-link--sub:hover) {
  background: var(--bg);
  color: var(--accent);
  text-decoration: none;
}

:deep(.nav-link--main.router-link-active),
:deep(.nav-link--sub.router-link-active) {
  background: rgba(59, 130, 246, 0.12);
  color: var(--accent);
  font-weight: 500;
}

:deep(.nav-link--main .app-icon),
:deep(.nav-link--sub .app-icon) {
  opacity: 0.85;
}

:deep(.nav-link--main.router-link-active .app-icon),
:deep(.nav-link--sub.router-link-active .app-icon) {
  opacity: 1;
}

:deep(.nav-link--main .nav-label) {
  line-height: 1.3;
}

:deep(.nav-link--sub .nav-label) {
  line-height: 1.25;
}

.logout-btn {
  margin-top: auto;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  padding: 0.7rem 0.9rem;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.04) 0%, transparent 100%);
  color: var(--muted);
  font-size: 0.9rem;
  font-weight: 500;
  cursor: pointer;
  transition:
    border-color 0.15s,
    color 0.15s,
    background 0.15s,
    box-shadow 0.15s;
}

.logout-btn:hover {
  border-color: rgba(239, 68, 68, 0.45);
  color: #fecaca;
  background: rgba(239, 68, 68, 0.1);
  box-shadow: 0 0 0 1px rgba(239, 68, 68, 0.12);
}

.logout-btn:active {
  transform: translateY(1px);
}

.logout-label {
  flex: 1;
  text-align: left;
}

.logout-icon {
  flex-shrink: 0;
  opacity: 0.9;
}

.logout-btn:hover .logout-icon {
  color: #f87171;
}

.main {
  flex: 1;
  padding: 2rem;
  max-width: 960px;
}
</style>
