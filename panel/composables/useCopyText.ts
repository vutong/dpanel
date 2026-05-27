/** Copy text to clipboard with brief UI feedback. */
export function useCopyText() {
  const copyFeedback = ref('')

  let feedbackTimer: ReturnType<typeof setTimeout> | undefined

  function setFeedback(msg: string, ms = 2000) {
    if (feedbackTimer) clearTimeout(feedbackTimer)
    copyFeedback.value = msg
    if (ms > 0) {
      feedbackTimer = setTimeout(() => {
        copyFeedback.value = ''
        feedbackTimer = undefined
      }, ms)
    }
  }

  async function copyText(text: string) {
    const value = text?.trim() ? text : ''
    if (!value) {
      setFeedback('Nothing to copy')
      return false
    }
    try {
      await navigator.clipboard.writeText(value)
      setFeedback('Copied')
      return true
    } catch {
      try {
        const ta = document.createElement('textarea')
        ta.value = value
        ta.style.position = 'fixed'
        ta.style.left = '-9999px'
        document.body.appendChild(ta)
        ta.select()
        document.execCommand('copy')
        document.body.removeChild(ta)
        setFeedback('Copied')
        return true
      } catch {
        setFeedback('Copy failed')
        return false
      }
    }
  }

  onUnmounted(() => {
    if (feedbackTimer) clearTimeout(feedbackTimer)
  })

  return { copyFeedback, copyText }
}
