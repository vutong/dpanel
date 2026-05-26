<template>
  <div class="page-loader" role="status" aria-live="polite" aria-busy="true">
    <div class="page-loader-spinner" aria-hidden="true" />
    <p v-if="label" class="page-loader-label">{{ label }}</p>
  </div>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    label?: string
  }>(),
  { label: 'Loading…' }
)
</script>

<style scoped>
.page-loader {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 1rem;
  min-height: 12rem;
  padding: 2rem 1rem;
}

.page-loader-spinner {
  width: 2.25rem;
  height: 2.25rem;
  border: 3px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: page-loader-spin 0.75s linear infinite;
}

.page-loader-label {
  font-size: 0.9rem;
  color: var(--muted);
  margin: 0;
}

@keyframes page-loader-spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
