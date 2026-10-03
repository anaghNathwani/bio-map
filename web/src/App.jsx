import React, { useEffect, useRef, useState, useCallback } from 'react'
import L from 'leaflet'
import 'leaflet'
import 'leaflet/dist/leaflet.css'
import 'leaflet.markercluster/dist/MarkerCluster.css'
import 'leaflet.markercluster/dist/MarkerCluster.Default.css'
import FilterBar from './components/FilterBar.jsx'
import SightingPopup from './components/SightingPopup.jsx'
import { fetchSightings } from './firebase.js'
import usePageMeta from './lib/pageMeta.js'
import './App.css'

const photoIcon = L.divIcon({
  html: `<div class="marker-dot marker-dot--photo"></div>`,
  className: '',
  iconSize: [14, 14],
  iconAnchor: [7, 7],
})

const audioIcon = L.divIcon({
  html: `<div class="marker-dot marker-dot--audio"></div>`,
  className: '',
  iconSize: [14, 14],
  iconAnchor: [7, 7],
})

export default function App() {
  usePageMeta('/map')
  const mapRef = useRef(null)
  const leafletRef = useRef(null)
  const clusterRef = useRef(null)
  const markersRef = useRef({})
  const [sightings, setSightings] = useState([])
  const [filtered, setFiltered] = useState([])
  const [selected, setSelected] = useState(null)
  const [count, setCount] = useState(0)

  // Init map
  useEffect(() => {
    if (leafletRef.current) return
    const map = L.map(mapRef.current, { center: [39.5, -98.35], zoom: 4 })
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© <a href="https://openstreetmap.org">OpenStreetMap</a>',
      className: 'map-tiles',
    }).addTo(map)

    // Dark tile overlay
    map.getContainer().style.filter = 'brightness(0.85) saturate(1.1)'

    leafletRef.current = map

    // Use plain L.LayerGroup since MarkerCluster may not be available as ESM
    let cluster
    try {
      // eslint-disable-next-line no-undef
      cluster = L.markerClusterGroup({ chunkedLoading: true })
    } catch {
      cluster = L.layerGroup()
    }
    cluster.addTo(map)
    clusterRef.current = cluster

    return () => { map.remove(); leafletRef.current = null }
  }, [])

  // Fetch sightings from Firestore
  const loadSightings = useCallback(async () => {
    try {
      const data = await fetchSightings(500)
      setSightings(data)
      setCount(data.length)
    } catch (e) {
      console.warn('Firestore fetch failed:', e)
    }
  }, [])

  useEffect(() => {
    loadSightings()
    const interval = setInterval(loadSightings, 30000)
    return () => clearInterval(interval)
  }, [loadSightings])

  // Sync markers when filtered list changes
  useEffect(() => {
    if (!clusterRef.current) return
    const cluster = clusterRef.current
    cluster.clearLayers()
    markersRef.current = {}

    filtered.forEach(s => {
      const icon = s.mediaType === 'audio' ? audioIcon : photoIcon
      const marker = L.marker([s.latitude, s.longitude], { icon })
      marker.on('click', () => setSelected(s))
      cluster.addLayer(marker)
      markersRef.current[s.id] = marker
    })
  }, [filtered])
  return (
    <div className="app">
      <h1 className="sr-only">BioMap live bird sighting map</h1>
      <header className="app-header">
        <div>
          <div className="app-logo">🐦 BioMap</div>
          <div className="app-subtitle">Live community bird sightings</div>
        </div>
        <FilterBar sightings={sightings} onFiltered={setFiltered} />
        <div className="app-badge">{count} sightings</div>
      </header>

      <div className="map-container">
        <div ref={mapRef} className="map" />

        <div className="legend">
          <div className="legend-title">Sighting type</div>
          <div className="legend-row"><div className="legend-dot legend-dot--photo" /> Photo</div>
          <div className="legend-row"><div className="legend-dot legend-dot--audio" /> Audio</div>
        </div>

        {selected && (
          <SightingPopup sighting={selected} onClose={() => setSelected(null)} />
        )}
      </div>
    </div>
  )
}
