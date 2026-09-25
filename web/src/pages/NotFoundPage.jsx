import React from 'react'
import { Link } from 'react-router-dom'
import StaticPageHeader from '../components/StaticPageHeader.jsx'
import SiteFooter from '../components/SiteFooter.jsx'
import { NOT_FOUND_META } from '../notFoundMeta.js'
import usePageMeta from '../lib/pageMeta.js'
import './StaticPage.css'

export default function NotFoundPage() {
  usePageMeta(NOT_FOUND_META)
  return (
    <div className="static-page">
      <StaticPageHeader />
      <main id="main">
      <div className="static-page-hero">
        <h1 className="static-page-h1">Page not found</h1>
        <p className="static-page-sub">
          That page has flown off. Try the <Link to="/" className="underline">home page</Link> or the{' '}
          <Link to="/map" className="underline">live sighting map</Link>.
        </p>
      </div>
      </main>
      <SiteFooter />
    </div>
  )
}
