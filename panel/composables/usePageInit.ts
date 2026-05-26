/** Brief init gate so static pages show loader on first paint (matches data-driven pages). */
export function usePageInit() {
  const ready = ref(false)
  onMounted(() => {
    ready.value = true
  })
  return { ready, loading: computed(() => !ready.value) }
}
