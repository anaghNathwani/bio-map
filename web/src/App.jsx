import React, { useEffect, useRef, useState, useCallback } from 'react'
import L from 'leaflet'
import 'leaflet'
import FilterBar from './components/FilterBar.jsx'
import SightingPopup from './components/SightingPopup.jsx'
import { fetchSightings } from './firebase.js'

const photoIcon = L.divIcon({
  html: `<div style="background:#0d9488;border:2px solid white;border-radius:50%;width:14px;height:14px;box-shadow:0 1px 4px rgba(0,0,0,.4)"></div>`,
  className: '',
  iconSize: [14, 14],
  iconAnchor: [7, 7],
})

const audioIcon = L.divIcon({
  html: `<div style="background:#8b5cf6;border:2px solid white;border-radius:50%;width:14px;height:14px;box-shadow:0 1px 4px rgba(0,0,0,.4)"></div>`,
  className: '',
  iconSize: [14, 14],
  iconAnchor: [7, 7],
})

const styles = {
  app: { height: '100vh', display: 'flex', flexDirection: 'column' },
  header: {
    padding: '12px 20px',
    background: 'linear-gradient(135deg,#0d9488,#0369a1)',
    display: 'flex',
    alignItems: 'center',
    gap: 12,
    boxShadow: '0 2px 8px rgba(0,0,0,.3)',
    zIndex: 1000,
  },
  logo: { fontSize: 22, fontWeight: 700, color: '#fff', display: 'flex', alignItems: 'center', gap: 8 },
  subtitle: { fontSize: 12, color: 'rgba(255,255,255,.75)', marginTop: 1 },
  badge: {
    marginLeft: 'auto', background: 'rgba(255,255,255,.2)', color: '#fff',
    padding: '3px 10px', borderRadius: 20, fontSize: 12, fontWeight: 600,
  },
  mapContainer: { flex: 1, position: 'relative' },
  map: { width: '100%', height: '100%' },
  legend: {
    position: 'absolute', bottom: 30, right: 10, zIndex: 1000,
    background: 'rgba(15,17,23,.85)', backdropFilter: 'blur(8px)',
    borderRadius: 10, padding: '10px 14px', fontSize: 12, color: '#e8eaf0',
    border: '1px solid rgba(255,255,255,.1)',
  },
  legendRow: { display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 },
  dot: (color) => ({ width: 10, height: 10, borderRadius: '50%', background: color, flexShrink: 0 }),
}

export default function App() {
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
//  <a href="/" style={styles.back}>🐦 BirdMap</a>
  return (
    <div style={styles.app}>
      <header style={styles.header}>
        <div>
          <div style={styles.logo}>🐦 BirdMap</div>
          <div style={styles.subtitle}>Live community bird sightings</div>
        </div>
        <FilterBar sightings={sightings} onFiltered={setFiltered} />
        <div style={styles.badge}>{count} sightings</div>
      </header>

      <div style={styles.mapContainer}>
        <div ref={mapRef} style={styles.map} />

        <div style={styles.legend}>
          <div style={{ fontWeight: 600, marginBottom: 6, color: '#94a3b8', fontSize: 11, textTransform: 'uppercase', letterSpacing: 1 }}>Sighting type</div>
          <div style={styles.legendRow}><div style={styles.dot('#0d9488')} /> Photo</div>
          <div style={styles.legendRow}><div style={styles.dot('#8b5cf6')} /> Audio</div>
        </div>

        {selected && (
          <SightingPopup sighting={selected} onClose={() => setSelected(null)} />
        )}
      </div>
    </div>
  )
}
