import React from 'react'
import { Link } from 'react-router-dom'
import { Info } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'

export default function AboutPage() {
  return (
    <ContentPage
      meta="/about"
      icon={Info}
      title="About BirdRadar"
      intro="A citizen science project for people who notice birds."
    >
      <h2 className="static-page-h2">What we are building</h2>
      <p className="static-page-p">
        BirdRadar turns everyday bird sightings into a living dataset: identified on your phone, verified by a
        community, and mapped for everyone. See <Link to="/how-it-works" className="underline">how it works</Link>.
      </p>

      <h2 className="static-page-h2">Principles</h2>
      <div className="static-page-card">
        <h3 className="static-page-card-title">Identification stays on your device</h3>
        <p className="static-page-card-body">
          Photo and sound identification run locally, so you get a suggestion without sending your photo or recording anywhere first.
        </p>
      </div>
      <div className="static-page-card">
        <h3 className="static-page-card-title">Honest about uncertainty</h3>
        <p className="static-page-card-body">
          When a model is not confident it says so. Community review exists because no model is right every time.
        </p>
      </div>
      <div className="static-page-card">
        <h3 className="static-page-card-title">Proven models, used as released</h3>
        <p className="static-page-card-body">
          Species suggestions come from Google&rsquo;s AIY Birds and Cornell Lab of Ornithology&rsquo;s BirdNET. Read the{' '}
          <Link to="/ai" className="underline">details of the AI</Link> and its limits.
        </p>
      </div>
      <div className="static-page-card">
        <h3 className="static-page-card-title">Your data, clearly explained</h3>
        <p className="static-page-card-body">
          See exactly what is stored and who can see it in our <Link to="/privacy" className="underline">privacy notice</Link> and{' '}
          <Link to="/terms" className="underline">terms</Link>.
        </p>
      </div>
    </ContentPage>
  )
}
