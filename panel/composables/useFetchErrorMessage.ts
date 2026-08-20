/** Extract a user-facing message from $fetch / ofetch errors and `{ ok: false, error }` payloads. */
export function fetchApiErrorMessage(e: unknown, fallback = 'Request failed'): string {
  if (e && typeof e === 'object') {
    const err = e as {
      data?: { statusMessage?: string; message?: string; error?: string }
      statusMessage?: string
      message?: string
      error?: string
    }
    if (typeof err.error === 'string' && err.error) return err.error
    if (err.data?.error) return err.data.error
    if (err.data?.statusMessage) return err.data.statusMessage
    if (err.statusMessage) return err.statusMessage
    if (err.data?.message) return err.data.message
    if (err.message && !/^\[(GET|POST|PUT|DELETE|PATCH)\]/i.test(err.message)) {
      return err.message
    }
  }
  return fallback
}
