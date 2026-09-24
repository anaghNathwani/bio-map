import React, { useState } from 'react'
import { Sun, Moon } from 'lucide-react'
import { getEffectiveTheme, setTheme } from '../lib/theme.js'

export default function ThemeToggle({ className = '' }) {
  const [theme, setThemeState] = useState(getEffectiveTheme)

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
      className={`inline-flex h-8 w-8 flex-none items-center justify-center border border-[var(--rule)] text-[var(--ink-soft)] transition-colors hover:border-[var(--ink)] hover:text-[var(--ink)] ${className}`}
    >
      {theme === 'dark' ? <Sun size={15} strokeWidth={1.75} /> : <Moon size={15} strokeWidth={1.75} />}
    </button>
  )
}
