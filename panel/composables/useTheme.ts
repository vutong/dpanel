export type ThemeMode = 'dark' | 'light'

const STORAGE_KEY = 'dpanel-theme'

export function useTheme() {
  const theme = useState<ThemeMode>('dpanel-theme', () => 'dark')

  function applyTheme(mode: ThemeMode) {
    theme.value = mode
    if (import.meta.client) {
      document.documentElement.setAttribute('data-theme', mode)
      localStorage.setItem(STORAGE_KEY, mode)
    }
  }

  function toggleTheme() {
    applyTheme(theme.value === 'dark' ? 'light' : 'dark')
  }

  function initTheme() {
    if (!import.meta.client) return
    const stored = localStorage.getItem(STORAGE_KEY) as ThemeMode | null
    const mode = stored === 'light' || stored === 'dark' ? stored : 'dark'
    applyTheme(mode)
  }

  return { theme, applyTheme, toggleTheme, initTheme }
}
