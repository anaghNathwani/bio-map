import React from 'react'
import { Link } from 'react-router-dom'
import { ShieldCheck } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'
import { CONTACT_EMAIL } from '../site.js'

const ROWS = [
  ['Your account',
    'Email address and username, plus a password or an Apple/Google sign-in. Your email is never shown publicly. Your username is visible next to your sightings and annotations.'],
  ['Sightings you submit',
    'The photo or recording, the notes you add, the time, and the location of the sighting. Submitted sightings are visible to other BioMap users and on the public map.'],
  ['Annotations',
    'Species IDs and details you add to sightings, and the resulting leaderboard totals, are visible to other users.'],
  ['Identification on your device',
    'Photo and sound identification run on your phone. A photo or recording only leaves your device when you choose to submit the sighting.'],
  ['Your location',
    'The app asks for location permission to pin a sighting and to narrow audio identification to species found near you. It is stored with the sighting you submit.'],
  ['Where data is stored',
    'Accounts and sightings are stored with Google Firebase (Authentication and Firestore).'],
]

export default function PrivacyPage() {
  return (
    <ContentPage
      meta="/privacy"
      icon={ShieldCheck}
      title="Privacy notice"
      intro="A plain-language summary of what BioMap handles. Last updated September 2026."
    >
      {ROWS.map(([title, body]) => (
        <section key={title} className="static-page-card">
          <h2 className="static-page-card-title">{title}</h2>
          <p className="static-page-card-body">{body}</p>
        </section>
      ))}
      <p className="static-page-p" style={{ marginTop: 32 }}>
        These points sit alongside the <Link to="/terms" className="underline">Terms of Service</Link>.
        {CONTACT_EMAIL && (
          <> Questions or requests about your data: <a href={`mailto:${CONTACT_EMAIL}`} className="underline">{CONTACT_EMAIL}</a>.</>
        )}
      </p>
    </ContentPage>
  )
}
