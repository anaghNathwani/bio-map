import React from 'react'
import StaticPageHeader from './StaticPageHeader.jsx'
import SiteFooter from './SiteFooter.jsx'
import RelatedLinks from './RelatedLinks.jsx'
import usePageMeta from '../lib/pageMeta.js'
import { routeFor, relatedFor } from '../site.js'
import '../pages/StaticPage.css'

/** Shared shell for text content pages: header, hero (h1 + intro), body, footer. */
export default function ContentPage({ meta, icon: Icon, title, intro, children }) {
  usePageMeta(meta)
  const route = typeof meta === 'string' ? routeFor(meta) : meta
  return (
    <div className="static-page">
      <StaticPageHeader />
      <main id="main">
        <div className="static-page-hero">
          {Icon && (
            <div className="static-page-icon">
              <Icon className="h-6 w-6" strokeWidth={1.75} />
            </div>
          )}
          <h1 className="static-page-h1">{title}</h1>
          {intro && <p className="static-page-sub">{intro}</p>}
        </div>
        <div className="static-page-section">
          {children}
          {route && <RelatedLinks paths={relatedFor(route)} />}
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
