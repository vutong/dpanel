const TOKEN_PREFIX = 'dpanel-github-token:'
const SAVE_PREFIX = 'dpanel-github-save-token:'

function storageKey(domain: string, prefix: string) {
  return `${prefix}${domain.trim().toLowerCase()}`
}

export function useGitHubTokenStorage() {
  function getSavePreference(domain: string): boolean {
    if (!import.meta.client) return false
    try {
      return localStorage.getItem(storageKey(domain, SAVE_PREFIX)) === '1'
    } catch {
      return false
    }
  }

  function getSavedToken(domain: string): string {
    if (!import.meta.client || !getSavePreference(domain)) return ''
    try {
      return localStorage.getItem(storageKey(domain, TOKEN_PREFIX)) || ''
    } catch {
      return ''
    }
  }

  function persist(domain: string, token: string, save: boolean) {
    if (!import.meta.client) return
    const tokenKey = storageKey(domain, TOKEN_PREFIX)
    const saveKey = storageKey(domain, SAVE_PREFIX)
    try {
      if (save && token.trim()) {
        localStorage.setItem(tokenKey, token.trim())
        localStorage.setItem(saveKey, '1')
      } else {
        localStorage.removeItem(tokenKey)
        localStorage.removeItem(saveKey)
      }
    } catch {
      /* ignore quota / private mode */
    }
  }

  return { getSavePreference, getSavedToken, persist }
}
