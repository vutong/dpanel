<template>
  <div>
    <h1>phpMyAdmin</h1>
    <p class="muted">Quản lý MariaDB qua giao diện web. Mở tab mới.</p>
    <div class="card">
      <a v-if="url" :href="url" target="_blank" rel="noopener" class="btn btn-primary">
        Mở phpMyAdmin →
      </a>
      <p v-else class="muted">Đang lấy URL...</p>
      <p class="hint">URL: <code>{{ url || '...' }}</code></p>
    </div>
  </div>
</template>

<script setup lang="ts">
const { data } = await useFetch<{ url: string }>('/api/phpmyadmin')
const url = computed(() => data.value?.url)
</script>

<style scoped>
.muted { color: var(--muted); margin: 0.5rem 0 1rem; }
.hint { margin-top: 1rem; font-size: 0.85rem; color: var(--muted); }
</style>
