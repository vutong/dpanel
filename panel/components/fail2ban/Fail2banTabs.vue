<template>
  <div class="f2b-tabs">
    <div class="tab-bar" role="tablist">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        type="button"
        role="tab"
        class="tab-btn"
        :class="{ active: modelValue === tab.id, disabled: tab.disabled }"
        :disabled="tab.disabled"
        @click="!tab.disabled && emit('update:modelValue', tab.id)"
      >
        {{ tab.label }}
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
export type Fail2banTabId = 'overview' | 'jails' | 'banned' | 'logs' | 'guide'

defineProps<{
  modelValue: Fail2banTabId
  tabs: { id: Fail2banTabId; label: string; disabled?: boolean }[]
}>()

const emit = defineEmits<{ 'update:modelValue': [Fail2banTabId] }>()
</script>

<style scoped>
.tab-bar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
  margin-bottom: 1rem;
  border-bottom: 1px solid var(--border);
  padding-bottom: 0.25rem;
}

.tab-btn {
  border: none;
  background: transparent;
  color: var(--muted);
  font-family: inherit;
  font-size: var(--text-md);
  padding: 0.5rem 0.75rem;
  border-radius: 6px 6px 0 0;
  cursor: pointer;
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
}

.tab-btn:hover:not(.disabled) {
  color: var(--text);
  background: var(--surface-2);
}

.tab-btn.active {
  color: var(--accent);
  border-bottom-color: var(--accent);
  font-weight: 600;
}

.tab-btn.disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
</style>
