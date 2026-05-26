<template>
  <NuxtLink :to="to" class="nav-link">
    <AppIcon :name="icon" :size="18" />
    <span class="nav-label">{{ label }}</span>
  </NuxtLink>
</template>

<script setup lang="ts">
defineProps<{
  to: string
  icon: string
  label: string
}>()
</script>
