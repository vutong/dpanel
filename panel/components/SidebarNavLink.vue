<template>
  <NuxtLink
    :to="to"
    :class="sub ? 'nav-link nav-link--sub' : 'nav-link nav-link--main'"
    :exact="to === '/'"
  >
    <span v-if="emoji" class="nav-emoji" aria-hidden="true">{{ emoji }}</span>
    <AppIcon v-else :name="icon!" :size="sub ? 16 : 18" class="nav-icon" />
    <span class="nav-label">{{ label }}</span>
  </NuxtLink>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    to: string
    icon?: string
    emoji?: string
    label: string
    sub?: boolean
  }>(),
  { sub: true, icon: 'file' }
)
</script>

<style scoped>
.nav-link {
  display: flex;
  align-items: center;
}

.nav-emoji {
  flex-shrink: 0;
  width: 1.125rem;
  text-align: center;
  font-size: 0.95rem;
  line-height: 1;
}

.nav-icon {
  flex-shrink: 0;
}

.nav-label {
  line-height: 1.2;
}
</style>
