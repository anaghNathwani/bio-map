import React from 'react'
import { Link } from 'react-router-dom'
import StaticPageHeader from '../components/StaticPageHeader.jsx'
import usePageMeta from '../lib/pageMeta.js'
import './StaticPage.css'

export const NOT_FOUND_META = {
  path: '/404',
  title: 'Page not found | BirdMap',
  description: 'The page you were looking for does not exist. Head back to the BirdMap home page or the live sighting map.',
  noindex: true,
}

export default function NotFoundPage() {
  usePageMeta(NOT_FOUND_META)
  return (
    <div className="static-page">
      <StaticPageHeader />
      <div className="static-page-hero">
        <h1 className="static-page-h1">Page not found</h1>
        <p className="static-page-sub">
          That page has flown off. Try the <Link to="/" className="underline">home page</Link> or the{' '}
          <Link to="/map" className="underline">live sighting map</Link>.
        </p>
      </div>
    </div>
  )
}
