import React, { useEffect, useState } from 'react'
import { Sun, Moon } from 'lucide-react'
import { getEffectiveTheme, getStoredTheme, setTheme } from '../lib/theme.js'

export default function ThemeToggle({ className = '' }) {
  // Always 'light' for the first render so server HTML and hydration agree;
  // the effect below syncs to the real theme right after mount.
  const [theme, setThemeState] = useState('light')

  // With no saved choice the page follows the OS, so keep the icon in step
  // when the OS preference flips (e.g. at sunset).
  useEffect(() => {
    setThemeState(getEffectiveTheme())
    const mq = window.matchMedia?.('(prefers-color-scheme: dark)')
    if (!mq) return
    const onChange = () => { if (!getStoredTheme()) setThemeState(getEffectiveTheme()) }
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])

  function toggle() {
    const next = theme === 'dark' ? 'light' : 'dark'
    setTheme(next)
    setThemeState(next)
  }

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
      className={`inline-flex h-8 w-8 flex-none items-center justify-center rounded-full text-[var(--fg-soft)] transition-colors hover:bg-[var(--bg-raised)] hover:text-[var(--fg)] ${className}`}
    >
      {theme === 'dark' ? <Sun size={15} strokeWidth={1.75} /> : <Moon size={15} strokeWidth={1.75} />}
    </button>
  )
}
