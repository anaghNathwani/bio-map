const KEY = 'bm-theme'

export function getStoredTheme() {
  try {
    const v = localStorage.getItem(KEY)
    return v === 'light' || v === 'dark' ? v : null
  } catch {
    return null
  }
}

/** The theme actually in effect right now: the visitor's explicit choice, or
 *  their OS preference when they haven't picked one. */
export function getEffectiveTheme() {
  const stored = getStoredTheme()
  if (stored) return stored
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

/** Explicitly pin the theme (persists across visits and overrides the OS). */
export function setTheme(theme) {
  try {
    localStorage.setItem(KEY, theme)
  } catch {
    // Private browsing / storage disabled — theme just won't persist.
  }
  document.documentElement.setAttribute('data-theme', theme)
}
