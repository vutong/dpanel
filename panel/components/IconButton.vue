<template>
  <button
    type="button"
    class="icon-btn"
    :class="`icon-btn--${variant}`"
    :data-tip="title"
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
    /** @deprecated Use disabled only — avoids flicker when toggled with disabled */
    busy?: boolean
  }>(),
  {
    variant: 'default',
    size: 18,
    disabled: false
  }
)

defineEmits<{ click: [event: MouseEvent] }>()
</script>

<style scoped>
.icon-btn {
  position: relative;
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

/* Instant tooltip (native title has ~1s browser delay). */
.icon-btn[data-tip]::after {
  content: attr(data-tip);
  position: absolute;
  right: calc(100% + 0.45rem);
  top: 50%;
  transform: translateY(-50%);
  padding: 0.3rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 500;
  line-height: 1.25;
  white-space: nowrap;
  border-radius: 6px;
  border: 1px solid var(--border);
  background: var(--surface);
  color: var(--text);
  box-shadow: var(--shadow-sm);
  opacity: 0;
  visibility: hidden;
  pointer-events: none;
  z-index: 200;
  transition: none;
}

.icon-btn[data-tip]:hover::after,
.icon-btn[data-tip]:focus-visible::after {
  opacity: 1;
  visibility: visible;
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
</style>
