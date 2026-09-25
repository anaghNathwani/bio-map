import React from 'react'
import birdMark from '../assets/bird-mark.svg'
import ThemeToggle from './ThemeToggle.jsx'

export default function StaticPageHeader() {
  return (
    <header className="static-page-header">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[60] focus:bg-[var(--ink)] focus:px-3 focus:py-2 focus:text-[var(--paper)]">Skip to content</a>
      <a href="/" className="static-page-back">← Home</a>
      <span className="static-page-logo">
        <a href="/" className="static-page-back"><img src={birdMark} alt="" width="18" height="18" />BirdMap</a>
      </span>
      <ThemeToggle className="ml-auto" />
    </header>
  )
}
