const CREATE_OP_SESSION_KEY = 'dpanel:create-op'

export type CreateOpSession = {
  domain: string
  op: 'create' | 'rebuild'
  runtime: string
  buildApp: boolean
}

export function useCreateOpSession() {
  function save(session: CreateOpSession) {
    if (!import.meta.client) return
    try {
      sessionStorage.setItem(CREATE_OP_SESSION_KEY, JSON.stringify(session))
    } catch {
      /* ignore quota / private mode */
    }
  }

  function load(): CreateOpSession | null {
    if (!import.meta.client) return null
    try {
      const raw = sessionStorage.getItem(CREATE_OP_SESSION_KEY)
      if (!raw) return null
      const parsed = JSON.parse(raw) as Partial<CreateOpSession>
      const domain = String(parsed.domain || '')
        .trim()
        .toLowerCase()
      if (!domain) return null
      const op = parsed.op === 'rebuild' ? 'rebuild' : 'create'
      return {
        domain,
        op,
        runtime: String(parsed.runtime || ''),
        buildApp: parsed.buildApp === true
      }
    } catch {
      return null
    }
  }

  function clear() {
    if (!import.meta.client) return
    try {
      sessionStorage.removeItem(CREATE_OP_SESSION_KEY)
    } catch {
      /* ignore */
    }
  }

  function updateOp(op: 'create' | 'rebuild') {
    const current = load()
    if (!current) return
    save({ ...current, op })
  }

  return { save, load, clear, updateOp }
}
