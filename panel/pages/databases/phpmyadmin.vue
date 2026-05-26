<template>
  <div>
    <h1>phpMyAdmin</h1>
    <p class="muted">Manage MariaDB in the browser. Opens in a new tab.</p>
    <PageLoader v-if="pending" label="Loading…" />
    <div v-else class="card">
      <a v-if="url" :href="url" target="_blank" rel="noopener" class="btn btn-primary">
        Open phpMyAdmin →
      </a>
      <p v-else class="muted">Could not resolve phpMyAdmin URL.</p>
      <p v-if="url" class="hint">URL: <code>{{ url }}</code></p>
    </div>
  </div>
</template>

<script setup lang="ts">
const { data, pending } = useFetch<{ url: string }>('/api/phpmyadmin')
const url = computed(() => data.value?.url)
</script>

<style scoped>
.muted { color: var(--muted); margin: 0.5rem 0 1rem; }
.hint { margin-top: 1rem; font-size: 0.85rem; color: var(--muted); }
</style>
