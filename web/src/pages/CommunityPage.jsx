import React from 'react'
import { Users } from 'lucide-react'
import StaticPageHeader from '../components/StaticPageHeader.jsx'
import SiteFooter from '../components/SiteFooter.jsx'
import usePageMeta from '../lib/pageMeta.js'
import './StaticPage.css'
import './CommunityPage.css'

export default function CommunityPage() {
  usePageMeta('/community')
  return (
    <div className="static-page">
      <StaticPageHeader />

      <main id="main">
      <div className="static-page-hero">
        <div className="static-page-icon"><Users className="h-6 w-6" strokeWidth={1.75} /></div>
        <h1 className="static-page-h1">Community Annotations</h1>
        <p className="static-page-sub">
          Every sighting on BirdRadar can be reviewed and verified by the community,
          making the data more accurate over time.
        </p>
      </div>

      <div className="static-page-section">
        <h2 className="static-page-h2">How annotations work</h2>
        <p className="static-page-p">
          When you or another user submits a sighting, the community can open it and
          add an annotation — confirming or correcting the species, describing
          behaviour, and assigning a confidence level. Multiple annotations on the
          same sighting create a consensus that improves data quality for everyone.
        </p>

        <h2 className="static-page-h2">The annotation process</h2>
        <ul className="community-page-steps">
          <li className="community-page-step">
            <div className="community-page-step-num">1</div>
            <div className="community-page-step-text">
              <div className="community-page-step-title">Browse the map</div>
              <div className="community-page-step-body">Tap any marker on the BirdRadar community map to open a sighting — photo or audio.</div>
            </div>
          </li>
          <li className="community-page-step">
            <div className="community-page-step-num">2</div>
            <div className="community-page-step-text">
              <div className="community-page-step-title">Review the evidence</div>
              <div className="community-page-step-body">Look at the photo or listen to the recording, and note the AI's suggested species identification.</div>
            </div>
          </li>
          <li className="community-page-step">
            <div className="community-page-step-num">3</div>
            <div className="community-page-step-text">
              <div className="community-page-step-title">Add your annotation</div>
              <div className="community-page-step-body">Confirm or correct the species, note the behaviour you observe, and set your confidence level (low / medium / high).</div>
            </div>
          </li>
          <li className="community-page-step">
            <div className="community-page-step-num">4</div>
            <div className="community-page-step-text">
              <div className="community-page-step-title">Earn leaderboard points</div>
              <div className="community-page-step-body">Each annotation earns you a point on the community leaderboard, recognising your contribution to the science.</div>
            </div>
          </li>
        </ul>

        <h2 className="static-page-h2">Why it matters</h2>
        <p className="static-page-p">
          AI models are not perfect. Community review catches misidentifications,
          adds behavioural context that photos alone can't convey, and builds a
          layer of human expertise on top of automated suggestions — a growing,
          verified record that's more reliable than any single AI guess.
        </p>
      </div>

      </main>

      <SiteFooter />
    </div>
  )
}
