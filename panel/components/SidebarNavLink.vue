<template>
  <NuxtLink :to="to" class="nav-link nav-link--sub">
    <AppIcon :name="icon" :size="16" />
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
