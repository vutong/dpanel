export type ClamavScanStatus = 'running' | 'ok' | 'error'

export type ClamavScanSummary = {
  id: string
  target: string
  domain: string | null
  scanPath: string
  status: ClamavScanStatus
  startedAt: string
  finishedAt?: string
  infectedCount?: number
  error?: string
}

export type ClamavScanDetail = ClamavScanSummary & {
  infected?: { path: string; domain: string | null; relPath: string; line: string }[]
  logTail?: string
}

const POLL_MS = 4000

export function useClamavScan(options?: {
  onComplete?: (scan: ClamavScanDetail | ClamavScanSummary) => void
  showAlert?: (message: string, success: boolean) => void
}) {
  const activeScan = ref<ClamavScanSummary | null>(null)
  const selectedScan = ref<ClamavScanDetail | null>(null)
  const polling = ref(false)

  let timer: ReturnType<typeof setInterval> | undefined
  let pollScanId: string | null = null

  function stopPoll() {
    if (timer) {
      clearInterval(timer)
      timer = undefined
    }
    polling.value = false
    pollScanId = null
  }

  async function fetchActive(): Promise<ClamavScanSummary | null> {
    try {
      const res = await $fetch<{ scan?: ClamavScanSummary | null }>(
        '/api/security/clamav/scans?active=1'
      )
      activeScan.value = res.scan ?? null
      return activeScan.value
    } catch {
      return null
    }
  }

  async function fetchScan(id: string): Promise<ClamavScanDetail | null> {
    try {
      const res = await $fetch<{ scan?: ClamavScanDetail | null }>(
        `/api/security/clamav/scans?id=${encodeURIComponent(id)}`
      )
      if (res.scan) {
        selectedScan.value = res.scan
      }
      return res.scan ?? null
    } catch {
      return null
    }
  }

  async function pollTick() {
    if (!pollScanId) return

    const scan = await fetchScan(pollScanId)
    if (!scan) return

    activeScan.value = scan

    if (scan.status === 'running') return

    stopPoll()
    activeScan.value = null

    const infected = scan.infectedCount ?? 0
    if (options?.showAlert) {
      if (scan.status === 'error') {
        options.showAlert(scan.error || 'Scan failed', false)
      } else if (infected > 0) {
        options.showAlert(`${infected} infected file(s) — see Results or Security events`, false)
      } else {
        options.showAlert('Scan complete — no infections found', true)
      }
    }

    options?.onComplete?.(scan)
  }

  function startPoll(scanId: string) {
    stopPoll()
    pollScanId = scanId
    polling.value = true
    void pollTick()
    timer = setInterval(() => void pollTick(), POLL_MS)
  }

  async function startScan(opts?: { domain?: string; endpoint?: string }) {
    const domain = opts?.domain?.trim().toLowerCase()
    const url =
      opts?.endpoint ||
      (domain
        ? `/api/websites/${encodeURIComponent(domain)}/clamav-scan`
        : '/api/security/clamav/scan')

    const res = await $fetch<{
      accepted?: boolean
      scanId?: string
      message?: string
    }>(url, {
      method: 'POST',
      body: domain ? { background: true } : { domain, background: true }
    })

    if (!res.accepted || !res.scanId) {
      throw new Error(res.message || 'Scan already running')
    }

    startPoll(res.scanId)
    return res
  }

  async function resumePollIfRunning() {
    const active = await fetchActive()
    if (active?.status === 'running' && active.id) {
      startPoll(active.id)
    }
  }

  onUnmounted(() => stopPoll())

  return {
    activeScan,
    selectedScan,
    polling,
    startScan,
    startPoll,
    stopPoll,
    fetchActive,
    fetchScan,
    resumePollIfRunning
  }
}
