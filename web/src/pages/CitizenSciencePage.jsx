import React from 'react'
import { Globe, Camera, Mic, MapPin } from 'lucide-react'
import StaticPageHeader from '../components/StaticPageHeader.jsx'
import usePageMeta from '../lib/pageMeta.js'
import './StaticPage.css'

export default function CitizenSciencePage() {
  usePageMeta('/citizen-science')
  return (
    <div className="static-page">
      <StaticPageHeader />

      <div className="static-page-hero">
        <div className="static-page-icon"><Globe className="h-6 w-6" strokeWidth={1.75} /></div>
        <h1 className="static-page-h1">Citizen Science Bird Tracking</h1>
        <p className="static-page-sub">
          Every sighting you submit becomes part of a growing scientific dataset
          that researchers and conservationists rely on.
        </p>
      </div>

      <div className="static-page-section">
        <h2 className="static-page-h2">What is citizen science?</h2>
        <p className="static-page-p">
          Citizen science is the practice of public participation in scientific research.
          With BirdMap, anyone with a smartphone can contribute real observations that
          complement data collected by professional ornithologists. Your sightings — with
          their species, location, date, and photo or audio — feed directly into the
          community database.
        </p>

        <h2 className="static-page-h2">How your data is used</h2>
        <p className="static-page-p">
          Each submission is geotagged and timestamped, then stored in a shared Firestore
          database. Community members can annotate and verify species IDs, increasing the
          reliability of each record. Aggregated data can reveal migration patterns,
          population shifts, and range expansions over time.
        </p>

        <h2 className="static-page-h2">What you can contribute</h2>

        <div className="static-page-card">
          <div className="static-page-card-title"><Camera size={16} strokeWidth={1.75} /> Photo sightings</div>
          <div className="static-page-card-body">Capture a bird in the wild — BirdMap's on-device AI suggests the species and your photo is uploaded to the community map.</div>
        </div>
        <div className="static-page-card">
          <div className="static-page-card-title"><Mic size={16} strokeWidth={1.75} /> Audio recordings</div>
          <div className="static-page-card-body">Record a call or song when you can't see the bird clearly. Audio sightings appear on the map as purple markers and can be annotated by the community.</div>
        </div>
        <div className="static-page-card">
          <div className="static-page-card-title"><MapPin size={16} strokeWidth={1.75} /> Location data</div>
          <div className="static-page-card-body">Every sighting is tagged with GPS coordinates, making it possible to map species distributions across the country in real time.</div>
        </div>
      </div>

      <footer className="static-page-footer">© 2026 BirdMap · Citizen Science</footer>
    </div>
  )
}
