import React from 'react'

const styles = {
  page: { minHeight: '100vh', background: '#0f1117', color: '#e8eaf0', fontFamily: 'system-ui, sans-serif' },
  header: {
    padding: '16px 24px',
    background: 'linear-gradient(135deg,#0d9488,#0369a1)',
    display: 'flex', alignItems: 'center', gap: 12,
  },
  back: {
    color: '#fff', textDecoration: 'none', fontSize: 14, opacity: 0.85,
    display: 'flex', alignItems: 'center', gap: 6,
  },
  logo: { fontSize: 20, fontWeight: 700, color: '#fff', marginLeft: 'auto', marginRight: 'auto' },
  hero: {
    padding: '60px 24px 48px',
    textAlign: 'center',
    borderBottom: '1px solid rgba(255,255,255,.08)',
  },
  icon: { fontSize: 56, marginBottom: 20 },
  h1: { fontSize: 32, fontWeight: 700, margin: '0 0 12px', color: '#fff' },
  sub: { fontSize: 16, color: '#94a3b8', maxWidth: 520, margin: '0 auto' },
  section: { maxWidth: 720, margin: '0 auto', padding: '48px 24px' },
  h2: { fontSize: 20, fontWeight: 600, color: '#5eead4', margin: '0 0 12px' },
  p: { fontSize: 15, lineHeight: 1.7, color: '#cbd5e1', margin: '0 0 32px' },
  card: {
    background: 'rgba(255,255,255,.05)', border: '1px solid rgba(255,255,255,.08)',
    borderRadius: 12, padding: '20px 24px', marginBottom: 16,
  },
  cardTitle: { fontWeight: 600, fontSize: 15, color: '#fff', marginBottom: 4 },
  cardBody: { fontSize: 14, color: '#94a3b8', lineHeight: 1.6 },
  footer: { textAlign: 'center', padding: '24px', color: '#475569', fontSize: 13, borderTop: '1px solid rgba(255,255,255,.06)' },
}

export default function CitizenSciencePage() {
  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <a href="/" style={styles.back}>← Map</a>
        <span style={styles.logo}>🐦 BirdMap</span>
      </header>

      <div style={styles.hero}>
        <div style={styles.icon}>🌐</div>
        <h1 style={styles.h1}>Citizen Science Bird Tracking</h1>
        <p style={styles.sub}>
          Every sighting you submit becomes part of a growing scientific dataset
          that researchers and conservationists rely on.
        </p>
      </div>

      <div style={styles.section}>
        <h2 style={styles.h2}>What is citizen science?</h2>
        <p style={styles.p}>
          Citizen science is the practice of public participation in scientific research.
          With BirdMap, anyone with a smartphone can contribute real observations that
          complement data collected by professional ornithologists. Your sightings — with
          their species, location, date, and photo or audio — feed directly into the
          community database.
        </p>

        <h2 style={styles.h2}>How your data is used</h2>
        <p style={styles.p}>
          Each submission is geotagged and timestamped, then stored in a shared Firestore
          database. Community members can annotate and verify species IDs, increasing the
          reliability of each record. Aggregated data can reveal migration patterns,
          population shifts, and range expansions over time.
        </p>

        <h2 style={styles.h2}>What you can contribute</h2>

        <div style={styles.card}>
          <div style={styles.cardTitle}>📸 Photo sightings</div>
          <div style={styles.cardBody}>Capture a bird in the wild — BirdMap's on-device AI suggests the species and your photo is uploaded to the community map.</div>
        </div>
        <div style={styles.card}>
          <div style={styles.cardTitle}>🎙️ Audio recordings</div>
          <div style={styles.cardBody}>Record a call or song when you can't see the bird clearly. Audio sightings appear on the map as purple markers and can be annotated by the community.</div>
        </div>
        <div style={styles.card}>
          <div style={styles.cardTitle}>📍 Location data</div>
          <div style={styles.cardBody}>Every sighting is tagged with GPS coordinates, making it possible to map species distributions across the country in real time.</div>
        </div>
      </div>

      <footer style={styles.footer}>© 2026 BirdMap · Citizen Science</footer>
    </div>
  )
}
