/** Single page-level alert: replaces previous message immediately (no stacked/overlap). */
export function usePageAlert() {
  const msg = ref('')
  const ok = ref(false)
  const alertKey = ref(0)
  let dismissTimer: ReturnType<typeof setTimeout> | undefined

  function clearAlert() {
    if (dismissTimer) {
      clearTimeout(dismissTimer)
      dismissTimer = undefined
    }
    if (!msg.value) return
    msg.value = ''
    alertKey.value += 1
  }

  function scrollToPageAlert() {
    if (!import.meta.client) return
    const run = () => {
      const el = document.getElementById('page-alert')
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'start' })
        return
      }
      window.scrollTo({ top: 0, behavior: 'smooth' })
      document.documentElement.scrollTo({ top: 0, behavior: 'smooth' })
    }
    // Brief delay so modals (rebuild/update stream) can close before scroll.
    window.setTimeout(() => {
      nextTick(() => {
        requestAnimationFrame(() => {
          requestAnimationFrame(run)
        })
      })
    }, 150)
  }

  function showAlert(text: string, success = true, autoDismissMs = 0) {
    if (dismissTimer) {
      clearTimeout(dismissTimer)
      dismissTimer = undefined
    }
    msg.value = ''
    alertKey.value += 1
    ok.value = success
    nextTick(() => {
      msg.value = text
      alertKey.value += 1
      scrollToPageAlert()
      if (autoDismissMs > 0) {
        dismissTimer = setTimeout(clearAlert, autoDismissMs)
      }
    })
  }

  onUnmounted(() => {
    if (dismissTimer) clearTimeout(dismissTimer)
  })

  return { msg, ok, alertKey, clearAlert, showAlert }
}
