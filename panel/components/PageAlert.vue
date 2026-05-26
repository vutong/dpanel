<template>
  <Transition name="page-alert" mode="out-in">
    <p
      v-if="message"
      :key="alertKey"
      class="alert"
      :class="success ? 'alert-success' : 'alert-error'"
      role="status"
    >
      {{ message }}
    </p>
  </Transition>
</template>

<script setup lang="ts">
defineProps<{
  message: string
  success: boolean
  alertKey: number
}>()
</script>
