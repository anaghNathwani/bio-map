import React from 'react'
import { FileText } from 'lucide-react'
import StaticPageHeader from '../components/StaticPageHeader.jsx'
import SiteFooter from '../components/SiteFooter.jsx'
import usePageMeta from '../lib/pageMeta.js'
import { TERMS_INTRO, TERMS_SECTIONS, TERMS_UPDATED } from '../content/terms.js'
import './StaticPage.css'
import './TermsPage.css'

export default function TermsPage() {
  usePageMeta('/terms')
  return (
    <div className="static-page">
      <StaticPageHeader />

      <main id="main">
      <div className="static-page-hero">
        <div className="static-page-icon"><FileText className="h-6 w-6" strokeWidth={1.75} /></div>
        <h1 className="static-page-h1">Terms of Service</h1>
        <p className="static-page-sub">Please read these terms carefully before using BioMap.</p>
      </div>

      <div className="static-page-section">
        <p className="terms-page-updated">Last updated: {TERMS_UPDATED}</p>
        <p className="terms-page-intro">{TERMS_INTRO}</p>

        {TERMS_SECTIONS.map(section => (
          <div className="static-page-card" key={section.title}>
            <div className="static-page-card-title">{section.title}</div>
            {section.body.map((block, i) => Array.isArray(block) ? (
              <ul key={i} className="static-page-card-body terms-page-list">
                {block.map(item => <li key={item}>{item}</li>)}
              </ul>
            ) : (
              <div key={i} className="static-page-card-body terms-page-para">{block}</div>
            ))}
          </div>
        ))}
      </div>

      </main>

      <SiteFooter />
    </div>
  )
}
