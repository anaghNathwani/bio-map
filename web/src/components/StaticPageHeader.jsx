import React from 'react'
import birdMark from '../assets/bird-mark.svg'
import ThemeToggle from './ThemeToggle.jsx'

export default function StaticPageHeader() {
  return (
    <header className="static-page-header">
      <a href="/" className="static-page-back">← Home</a>
      <span className="static-page-logo">
        <a href="/" className="static-page-back"><img src={birdMark} alt="" />BirdMap</a>
      </span>
      <ThemeToggle className="ml-auto" />
    </header>
  )
}
