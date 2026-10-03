import React from 'react'
import { CircleHelp } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'
import { FAQ } from '../content/faq.js'

export default function FaqPage() {
  return (
    <ContentPage
      meta="/faq"
      icon={CircleHelp}
      title="Frequently asked questions"
      intro="How BirdRadar identifies birds, what happens to your sightings, and what it costs."
    >
      {FAQ.map(item => (
        <section key={item.q} className="static-page-card">
          <h2 className="static-page-card-title">{item.q}</h2>
          <p className="static-page-card-body">{item.a}</p>
        </section>
      ))}
    </ContentPage>
  )
}
