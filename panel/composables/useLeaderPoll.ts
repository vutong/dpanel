import { inject, type Ref } from 'vue'
import { PanelPresenceKey } from '~/composables/usePanelPresence'

export function useInjectedPresence(): { isLeader: Ref<boolean>; isVisible: Ref<boolean> } {
  const ctx = inject(PanelPresenceKey)
  if (ctx) return ctx
  const isLeader = ref(true)
  const isVisible = ref(true)
  return { isLeader, isVisible }
}

export function useLeaderPoll<T>(options: {
  channel: string
  intervalMs: number
  fetcher: () => Promise<T>
  onData: (data: T) => void
  onError?: (error: unknown) => void
  followerFallbackMs?: number
}) {
  const { isLeader, isVisible } = useInjectedPresence()

  let pollTimer: ReturnType<typeof setInterval> | null = null
  let fallbackTimer: ReturnType<typeof setInterval> | null = null
  let channel: BroadcastChannel | null = null
  let inFlight = false
  let lastMessageAt = 0

  async function leaderFetch() {
    if (inFlight || !isVisible.value || !isLeader.value) return
    inFlight = true
    try {
      const data = await options.fetcher()
      options.onData(data)
      lastMessageAt = Date.now()
      channel?.postMessage({ type: 'data', at: lastMessageAt, data })
    } catch (e) {
      options.onError?.(e)
    } finally {
      inFlight = false
    }
  }

  async function followerFallbackFetch() {
    if (inFlight || !isVisible.value || isLeader.value) return
    const fallbackMs = options.followerFallbackMs ?? 60_000
    if (Date.now() - lastMessageAt < fallbackMs) return
    inFlight = true
    try {
      const data = await options.fetcher()
      options.onData(data)
      lastMessageAt = Date.now()
    } catch {
      /* ignore */
    } finally {
      inFlight = false
    }
  }

  function onChannelMessage(ev: MessageEvent<{ type?: string; data?: T }>) {
    if (isLeader.value) return
    const msg = ev.data
    if (!msg || msg.type !== 'data') return
    lastMessageAt = Date.now()
    if (msg.data !== undefined) options.onData(msg.data)
  }

  watch(isLeader, (leader) => {
    if (leader && isVisible.value) void leaderFetch()
  })

  watch(isVisible, (visible) => {
    if (visible && isLeader.value) void leaderFetch()
  })

  onMounted(() => {
    if (!import.meta.client) return
    channel =
      typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel(options.channel) : null
    channel?.addEventListener('message', onChannelMessage)

    void leaderFetch()
    pollTimer = setInterval(() => void leaderFetch(), options.intervalMs)

    const fallbackMs = options.followerFallbackMs ?? 60_000
    fallbackTimer = setInterval(() => void followerFallbackFetch(), fallbackMs)
  })

  onUnmounted(() => {
    if (pollTimer) clearInterval(pollTimer)
    if (fallbackTimer) clearInterval(fallbackTimer)
    channel?.removeEventListener('message', onChannelMessage)
    channel?.close()
  })

  return { refresh: () => void leaderFetch() }
}
