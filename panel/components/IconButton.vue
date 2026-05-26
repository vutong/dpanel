<template>
  <button
    type="button"
    class="icon-btn"
    :class="[`icon-btn--${variant}`, { 'icon-btn--busy': busy }]"
    :title="title"
    :aria-label="title"
    :disabled="disabled || busy"
    @click="$emit('click', $event)"
  >
    <AppIcon :name="icon" :size="size" />
  </button>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    icon: string
    title: string
    variant?: 'default' | 'danger'
    size?: number
    disabled?: boolean
    busy?: boolean
  }>(),
  {
    variant: 'default',
    size: 18,
    disabled: false,
    busy: false
  }
)

defineEmits<{ click: [event: MouseEvent] }>()
</script>

<style scoped>
.icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.15rem;
  height: 2.15rem;
  padding: 0;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface-elevated);
  color: var(--text);
  cursor: pointer;
  transition:
    background 0.15s,
    border-color 0.15s,
    color 0.15s;
}

.icon-btn:hover:not(:disabled) {
  border-color: var(--accent);
  color: var(--accent);
  background: var(--accent-muted);
}

.icon-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.icon-btn--danger:hover:not(:disabled) {
  border-color: var(--danger);
  color: var(--danger);
  background: var(--danger-muted);
}

.icon-btn--busy {
  pointer-events: none;
}
</style>
