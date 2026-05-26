<template>
  <button
    type="button"
    class="theme-toggle"
    :title="theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'"
    :aria-label="theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'"
    @click="toggleTheme"
  >
    <AppIcon :name="theme === 'dark' ? 'sun' : 'moon'" :size="18" />
  </button>
</template>

<script setup lang="ts">
const { theme, toggleTheme } = useTheme()
</script>

<style scoped>
.theme-toggle {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  flex-shrink: 0;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface-elevated);
  color: var(--muted);
  cursor: pointer;
  transition:
    color 0.15s,
    border-color 0.15s,
    background 0.15s,
    box-shadow 0.15s;
}

.theme-toggle:hover {
  color: var(--accent);
  border-color: var(--accent);
  background: var(--accent-muted);
}
</style>
