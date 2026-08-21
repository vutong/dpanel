<template>
  <div>
    <h1>phpMyAdmin</h1>
    <p class="muted">Manage MariaDB in the browser. Opens in a new tab.</p>
    <div class="card" :aria-busy="listLoading">
      <template v-if="listLoading">
        <span class="skeleton skeleton-text-lg" style="width: 10rem; height: 2rem" aria-hidden="true" />
        <p class="hint">
          <span class="skeleton skeleton-line" style="width: 70%; margin-top: 1rem" aria-hidden="true" />
        </p>
      </template>
      <template v-else>
        <a v-if="url" :href="url" target="_blank" rel="noopener" class="btn btn-primary">
          Open phpMyAdmin →
        </a>
        <p v-else class="muted empty">Could not resolve phpMyAdmin URL.</p>
        <p v-if="url" class="hint">URL: <code>{{ url }}</code></p>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
const { data, pending } = useFetch<{ url: string }>('/api/phpmyadmin')
const url = computed(() => data.value?.url)
const listLoading = computed(() => pending.value)
</script>

<style scoped>
.muted { color: var(--muted); margin: 0.5rem 0 1rem; }
.empty { margin: 0; }
.hint { margin-top: 1rem; font-size: 0.85rem; color: var(--muted); }
</style>
