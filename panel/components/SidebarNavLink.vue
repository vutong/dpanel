<template>
  <NuxtLink
    :to="to"
    :class="sub ? 'nav-link nav-link--sub' : 'nav-link nav-link--main'"
    :exact="to === '/'"
  >
    <AppIcon :name="icon" :size="sub ? 16 : 18" class="nav-icon" />
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

<style scoped>
.nav-link {
  display: flex;
  align-items: center;
}

.nav-icon {
  flex-shrink: 0;
}

.nav-label {
  line-height: 1.2;
}
</style>
