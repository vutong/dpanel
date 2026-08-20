const POLL_MS = 5000

type InstallPollData = {
  installed?: boolean
  installStatus?: 'none' | 'running' | 'ok' | 'error'
  installMessage?: string
}

export function useSecurityInstallPoll(options: {
  load: () => Promise<void>
  data: Ref<InstallPollData | null>
  installBusy: Ref<boolean>
  showAlert: (message: string, success: boolean) => void
  successMessage: string
}) {
  let timer: ReturnType<typeof setInterval> | undefined

  function stopPoll() {
    if (timer) {
      clearInterval(timer)
      timer = undefined
    }
    options.installBusy.value = false
  }

  function handleInstallState() {
    const d = options.data.value
    if (!d) return

    if (d.installed) {
      stopPoll()
      options.showAlert(options.successMessage, true)
      return
    }

    const st = d.installStatus
    if (st === 'running') return

    if (st === 'ok') {
      stopPoll()
      options.showAlert(options.successMessage, true)
      return
    }

    if (st === 'error') {
      stopPoll()
      options.showAlert(d.installMessage || 'Install failed', false)
    }
  }

  async function pollTick() {
    try {
      await options.load()
    } catch {
      /* keep polling — transient load errors happen during long installs */
    }
    handleInstallState()
  }

  function startPoll() {
    options.installBusy.value = true
    void pollTick()
    if (timer) clearInterval(timer)
    timer = setInterval(() => void pollTick(), POLL_MS)
  }

  function resumePollIfRunning() {
    if (options.data.value?.installStatus === 'running') {
      startPoll()
    }
  }

  onUnmounted(() => stopPoll())

  return { startPoll, stopPoll, resumePollIfRunning }
}
