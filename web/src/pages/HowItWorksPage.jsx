import React from 'react'
import { Compass } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'
import '../pages/CommunityPage.css'

const STEPS = [
  ['Capture a bird',
    'Take or choose a photo, or record up to 30 seconds of a bird call. You can also upload an existing audio file; it is converted to a small clip and trimmed to the first 30 seconds.'],
  ['Identification runs on your phone',
    'Photos are classified by Google\u2019s AIY Birds model (about 960 species) and recordings by Cornell Lab of Ornithology\u2019s BirdNET. Both run on the device, so no photo or recording is sent anywhere just to get a suggestion. If the model is not confident it says so instead of guessing.'],
  ['Submit the sighting',
    'When you submit, the sighting is pinned to the map with its location and time. Location also improves audio results: BirdNET uses it to rule out species that do not live nearby.'],
  ['The community reviews it',
    'Anyone can add their own ID (an annotation) to a sighting, confirm the AI\u2019s guess, or mark it wrong or unsure. Several annotations on one sighting build a consensus that is more reliable than any single guess.'],
  ['Explore the live map',
    'The map shows one pin per place. A number on a pin means several sightings were reported there. Search by species, note, username or place.'],
]

export default function HowItWorksPage() {
  return (
    <ContentPage
      meta="/how-it-works"
      icon={Compass}
      title="How BirdRadar works"
      intro="From a photo or a call to a verified sighting on a shared map, in five steps."
    >
      <ul className="community-page-steps">
        {STEPS.map(([title, body], i) => (
          <li key={title} className="community-page-step">
            <div className="community-page-step-num">{i + 1}</div>
            <div className="community-page-step-text">
              <h2 className="community-page-step-title">{title}</h2>
              <div className="community-page-step-body">{body}</div>
            </div>
          </li>
        ))}
      </ul>

      <h2 className="static-page-h2">Where it is available</h2>
      <p className="static-page-p">
        The BirdRadar iOS app is coming soon to the App Store. The live sighting map already works in any web
        browser, and you can read more about the <a href="/bird-photo-identification" className="underline">photo</a> and{' '}
        <a href="/bird-sound-identification" className="underline">sound</a> identification behind it.
      </p>
    </ContentPage>
  )
}
