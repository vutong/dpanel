<template>
  <NuxtLink
    :to="to"
    :class="sub ? 'nav-link nav-link--sub' : 'nav-link nav-link--main'"
    :exact="to === '/'"
  >
    <AppIcon :name="icon" :size="sub ? 16 : 18" />
    <span class="nav-label">{{ label }}</span>
  </NuxtLink>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    to: string
    icon: string
    label: string
    sub?: boolean
  }>(),
  { sub: true }
)
</script>
