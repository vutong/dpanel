import { toValue, type InjectionKey, type MaybeRefOrGetter, type Ref } from 'vue'

export type PanelPresenceSection = 'dashboard' | 'databases' | 'websites' | 'settings'

export type PanelPresenceContext = {
  isLeader: Ref<boolean>
  isVisible: Ref<boolean>
}

export const PanelPresenceKey: InjectionKey<PanelPresenceContext> = Symbol('panelPresence')

const LEADER_STORAGE_KEY = 'dpanel-presence-leader'
const CHANNEL_NAME = 'dpanel-presence'
const HEARTBEAT_MS = 20_000
const LEADER_STALE_MS = 25_000

type LeaderRecord = { tabId: string; at: number }

type PresenceMessage =
  | { type: 'leader-resign'; tabId: string }
  | { type: 'leader-claim'; tabId: string; at: number }

function tabId(): string {
  if (!import.meta.client) return 'ssr'
  let id = sessionStorage.getItem('dpanel-presence-tab-id')
  if (!id) {
    id = crypto.randomUUID()
    sessionStorage.setItem('dpanel-presence-tab-id', id)
  }
  return id
}

function readLeader(): LeaderRecord | null {
  try {
    const raw = localStorage.getItem(LEADER_STORAGE_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as LeaderRecord
    if (!parsed?.tabId || typeof parsed.at !== 'number') return null
    return parsed
  } catch {
    return null
  }
}

function writeLeader(record: LeaderRecord): void {
  localStorage.setItem(LEADER_STORAGE_KEY, JSON.stringify(record))
}

export function usePanelPresence(options: {
  sections: MaybeRefOrGetter<PanelPresenceSection[]>
  domain?: MaybeRefOrGetter<string | undefined>
}) {
  const id = tabId()
  const isLeader = ref(false)
  const isVisible = ref(import.meta.client ? !document.hidden : true)

  const shouldPoll = computed(() => isVisible.value)

  let heartbeatTimer: ReturnType<typeof setInterval> | null = null
  let channel: BroadcastChannel | null = null

  function claimLeader(force = false): void {
    if (!import.meta.client || document.hidden) {
      isLeader.value = false
      return
    }
    const now = Date.now()
    const current = readLeader()
    const stale = !current || now - current.at > LEADER_STALE_MS
    if (force || stale || current.tabId === id) {
      writeLeader({ tabId: id, at: now })
      isLeader.value = true
      channel?.postMessage({ type: 'leader-claim', tabId: id, at: now } satisfies PresenceMessage)
      return
    }
    isLeader.value = current.tabId === id
  }

  function resignLeader(): void {
    if (!isLeader.value) return
    const current = readLeader()
    if (current?.tabId === id) {
      localStorage.removeItem(LEADER_STORAGE_KEY)
    }
    isLeader.value = false
    channel?.postMessage({ type: 'leader-resign', tabId: id } satisfies PresenceMessage)
  }

  async function sendPresence(): Promise<void> {
    if (!isLeader.value || document.hidden) return
    const sections = toValue(options.sections)
    if (!sections.length) return
    const body: { sections: PanelPresenceSection[]; domain?: string } = { sections }
    const domain = String(toValue(options.domain) || '')
      .trim()
      .toLowerCase()
    if (domain) body.domain = domain
    try {
      await $fetch('/api/internal/presence', { method: 'POST', body })
      writeLeader({ tabId: id, at: Date.now() })
    } catch {
      /* ignore transient errors */
    }
  }

  function onVisibilityChange(): void {
    isVisible.value = !document.hidden
    if (document.hidden) {
      resignLeader()
    } else {
      claimLeader(true)
      void sendPresence()
    }
  }

  function onChannelMessage(ev: MessageEvent<PresenceMessage>): void {
    const msg = ev.data
    if (!msg?.type) return
    if (msg.type === 'leader-resign' && msg.tabId !== id) {
      claimLeader(true)
      if (isLeader.value) void sendPresence()
    }
    if (msg.type === 'leader-claim' && msg.tabId !== id) {
      isLeader.value = false
    }
  }

  function onStorage(ev: StorageEvent): void {
    if (ev.key !== LEADER_STORAGE_KEY) return
    claimLeader()
  }

  watch(
    () => toValue(options.sections),
    () => {
      void sendPresence()
    },
    { deep: true }
  )

  onMounted(() => {
    if (!import.meta.client) return
    channel = typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel(CHANNEL_NAME) : null
    channel?.addEventListener('message', onChannelMessage)
    document.addEventListener('visibilitychange', onVisibilityChange)
    window.addEventListener('storage', onStorage)
    window.addEventListener('beforeunload', resignLeader)

    claimLeader(true)
    void sendPresence()
    heartbeatTimer = setInterval(() => {
      claimLeader()
      void sendPresence()
    }, HEARTBEAT_MS)
  })

  onUnmounted(() => {
    if (!import.meta.client) return
    if (heartbeatTimer) clearInterval(heartbeatTimer)
    document.removeEventListener('visibilitychange', onVisibilityChange)
    window.removeEventListener('storage', onStorage)
    window.removeEventListener('beforeunload', resignLeader)
    channel?.removeEventListener('message', onChannelMessage)
    channel?.close()
    resignLeader()
  })

  return { isLeader, isVisible, shouldPoll, sendPresence }
}
