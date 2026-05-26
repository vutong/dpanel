<template>
  <div class="layout">
    <aside v-if="showNav" class="sidebar">
      <div class="sidebar-head">
        <div class="brand">
          <AppIcon name="dashboard" :size="22" class="brand-icon" />
          <span class="brand-text">
            dpanel
            <span v-if="panelVersion" class="ver">v{{ panelVersion }}</span>
          </span>
        </div>
        <ThemeToggle />
      </div>

      <nav class="nav">
        <NuxtLink to="/" class="nav-section nav-section--link">
          <AppIcon name="overview" :size="14" class="section-icon" />
          Overview
        </NuxtLink>
        <hr class="nav-divider" aria-hidden="true" />

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

const { data: health } = useFetch<{ version?: string }>('/api/health', {
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
  background: var(--bg);
}

.sidebar {
  width: 248px;
  background: var(--surface);
  border-right: 1px solid var(--border);
  padding: 1.15rem 0.9rem;
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  box-shadow: var(--shadow-sm);
}

.sidebar-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-bottom: 1.15rem;
  padding: 0 0.15rem;
}

.brand {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  min-width: 0;
  flex: 1;
}

.brand-icon {
  color: var(--accent);
  flex-shrink: 0;
}

.brand-text {
  font-size: 1.15rem;
  font-weight: 700;
  line-height: 1.2;
  color: var(--text);
  letter-spacing: -0.02em;
}

.brand .ver {
  display: block;
  font-size: 0.65rem;
  font-weight: 500;
  color: var(--muted);
  margin-top: 0.1rem;
}

.nav {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 0.12rem;
}

.nav-section {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.68rem;
  text-transform: uppercase;
  color: var(--text);
  margin: 0.8rem 0 0.3rem 0.5rem;
  letter-spacing: 0.06em;
  font-weight: 600;
}

.nav-section:first-of-type {
  margin-top: 0;
}

.nav-section--link {
  text-decoration: none;
  color: var(--text);
  border-radius: 8px;
  padding: 0.45rem 0.5rem;
  margin: 0 0 0.15rem 0;
  transition: background 0.15s, color 0.15s;
}

.nav-section--link:hover {
  background: var(--accent-muted);
  color: var(--accent);
  text-decoration: none;
}

.nav-section--link.router-link-exact-active {
  background: var(--accent-muted);
  color: var(--accent);
}

.section-icon {
  opacity: 0.75;
}

.nav-section--link.router-link-exact-active .section-icon,
.nav-section--link:hover .section-icon {
  opacity: 1;
}

.nav-divider {
  border: none;
  border-top: 1px solid var(--border);
  margin: 0.65rem 0.25rem 0.75rem;
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
  margin-bottom: 0.3rem;
  border-radius: 9px;
  color: var(--muted);
  font-size: 0.9rem;
  font-weight: 500;
}

:deep(.nav-link--sub) {
  gap: 0.55rem;
  padding: 0.38rem 0.55rem 0.38rem 0.72rem;
  border-radius: 8px;
  color: var(--muted);
  font-size: 0.8rem;
}

:deep(.nav-link--main:hover),
:deep(.nav-link--sub:hover) {
  background: var(--accent-muted);
  color: var(--accent);
  text-decoration: none;
}

:deep(.nav-link--main.router-link-active),
:deep(.nav-link--sub.router-link-active) {
  background: var(--accent-muted);
  color: var(--accent);
  font-weight: 600;
}

:deep(.nav-link--main .app-icon),
:deep(.nav-link--sub .app-icon) {
  opacity: 0.88;
}

:deep(.nav-link--main.router-link-active .app-icon),
:deep(.nav-link--sub.router-link-active .app-icon) {
  opacity: 1;
}

.logout-btn {
  margin-top: auto;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  padding: 0.68rem 0.85rem;
  border-radius: 9px;
  border: 1px solid var(--border);
  background: var(--surface-elevated);
  color: var(--muted);
  font-size: 0.88rem;
  font-weight: 500;
  cursor: pointer;
  transition:
    border-color 0.15s,
    color 0.15s,
    background 0.15s;
}

.logout-btn:hover {
  border-color: var(--danger);
  color: var(--danger);
  background: var(--danger-muted);
}

.logout-btn:active {
  transform: translateY(1px);
}

.logout-label {
  flex: 1;
  text-align: left;
}

.main {
  flex: 1;
  min-width: 0;
  width: 100%;
  padding: 2rem 2.5rem 2.5rem;
  max-width: none;
}
</style>
