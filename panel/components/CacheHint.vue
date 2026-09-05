<template>
  <p v-if="hint" class="cache-hint" :class="stale ? 'pill pill-warn' : 'muted'">
    {{ hint }}
  </p>
</template>

<script setup lang="ts">
const props = defineProps<{
  cache?: CacheMetaFields | null
  warmingLabel?: string
  hasData?: boolean
}>()

const hint = computed(() =>
  formatCacheHint(props.cache, {
    warmingLabel: props.warmingLabel,
    hasData: props.hasData
  })
)
const stale = computed(() => Boolean(props.cache?.stale || props.cache?.warming))
</script>

<style scoped>
.cache-hint {
  font-size: var(--text-xs);
  margin: 0 0 0.65rem;
}
</style>
