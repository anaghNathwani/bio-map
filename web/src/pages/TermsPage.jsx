import React from 'react'
import { FileText } from 'lucide-react'
import StaticPageHeader from '../components/StaticPageHeader.jsx'
import './StaticPage.css'
import './TermsPage.css'

export default function TermsPage() {
  return (
    <div className="static-page">
      <StaticPageHeader />

      <div className="static-page-hero">
        <div className="static-page-icon"><FileText className="h-6 w-6" strokeWidth={1.75} /></div>
        <h1 className="static-page-h1">Terms of Service</h1>
        <p className="static-page-sub">Please read these terms carefully before using BirdMap.</p>
      </div>

      <div className="static-page-section">
        <p className="terms-page-updated">Last updated: August 2025</p>

        <div className="static-page-card">
          <div className="static-page-card-title">1. Data Use</div>
          <div className="static-page-card-body">Sightings and photos you submit are shared with the BirdMap community to support citizen science research. Location data is stored with each sighting.</div>
        </div>

        <div className="static-page-card">
          <div className="static-page-card-title">2. Conduct</div>
          <div className="static-page-card-body">You agree to submit accurate sightings and not misuse the platform. Spam, offensive content, or intentionally false reports may result in account removal.</div>
        </div>

        <div className="static-page-card">
          <div className="static-page-card-title">3. Privacy</div>
          <div className="static-page-card-body">Your email address is never shared publicly. Your username and sightings are visible to other users.</div>
        </div>

        <div className="static-page-card">
          <div className="static-page-card-title">4. Content</div>
          <div className="static-page-card-body">You retain ownership of photos you upload. By uploading, you grant BirdMap a license to display them within the app.</div>
        </div>

        <div className="static-page-card">
          <div className="static-page-card-title">5. Changes</div>
          <div className="static-page-card-body">These terms may be updated at any time. Continued use of the app constitutes acceptance of the updated terms.</div>
        </div>
      </div>

      <footer className="static-page-footer">© 2025 BirdMap · Citizen Science for Everyone</footer>
    </div>
  )
}
