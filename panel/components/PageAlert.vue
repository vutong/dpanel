<template>
  <Transition name="page-alert" mode="out-in">
    <div
      v-if="message"
      id="page-alert"
      :key="alertKey"
      class="alert page-alert"
      :class="success ? 'alert-success' : 'alert-error'"
      role="status"
    >
      <span class="page-alert__text">{{ message }}</span>
      <button
        type="button"
        class="page-alert__dismiss"
        aria-label="Dismiss notification"
        @click="emit('dismiss')"
      >
        <AppIcon name="x" :size="16" />
      </button>
    </div>
  </Transition>
</template>

<script setup lang="ts">
defineProps<{
  message: string
  success: boolean
  alertKey: number
}>()

const emit = defineEmits<{ dismiss: [] }>()
</script>

<style scoped>
.page-alert {
  display: flex;
  align-items: flex-start;
  gap: 0.75rem;
}

.page-alert__text {
  flex: 1;
  min-width: 0;
}

.page-alert__dismiss {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  margin: -0.15rem -0.25rem -0.15rem 0;
  padding: 0;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: inherit;
  opacity: 0.7;
  cursor: pointer;
}

.page-alert__dismiss:hover {
  opacity: 1;
  background: rgba(0, 0, 0, 0.08);
}

html[data-theme='dark'] .page-alert__dismiss:hover {
  background: rgba(255, 255, 255, 0.1);
}
</style>
