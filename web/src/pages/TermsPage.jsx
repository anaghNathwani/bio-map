import React from 'react'

const styles = {
  page: { minHeight: '100vh', background: '#0f1117', color: '#e8eaf0', fontFamily: 'system-ui, sans-serif' },
  header: {
    padding: '16px 24px',
    background: 'linear-gradient(135deg,#0d9488,#0369a1)',
    display: 'flex', alignItems: 'center', gap: 12,
  },
  back: { color: '#fff', textDecoration: 'none', fontSize: 14, opacity: 0.85 },
  logo: { fontSize: 20, fontWeight: 700, color: '#fff', marginLeft: 'auto', marginRight: 'auto' },
  hero: {
    padding: '60px 24px 48px', textAlign: 'center',
    borderBottom: '1px solid rgba(255,255,255,.08)',
  },
  icon: { fontSize: 56, marginBottom: 20 },
  h1: { fontSize: 32, fontWeight: 700, margin: '0 0 12px', color: '#fff' },
  sub: { fontSize: 16, color: '#94a3b8', maxWidth: 520, margin: '0 auto' },
  section: { maxWidth: 720, margin: '0 auto', padding: '48px 24px' },
  updated: { fontSize: 13, color: '#475569', marginBottom: 32 },
  card: {
    background: 'rgba(255,255,255,.05)', border: '1px solid rgba(255,255,255,.08)',
    borderRadius: 12, padding: '20px 24px', marginBottom: 16,
  },
  cardTitle: { fontWeight: 600, fontSize: 15, color: '#5eead4', marginBottom: 8 },
  cardBody: { fontSize: 14, color: '#cbd5e1', lineHeight: 1.7 },
  footer: { textAlign: 'center', padding: '24px', color: '#475569', fontSize: 13, borderTop: '1px solid rgba(255,255,255,.06)' },
}

export default function TermsPage() {
  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <a href="/" style={styles.back}>← Map</a>
        <span style={styles.logo}><a href="/" style={styles.back}>🐦 BirdMap</a></span>
      </header>

      <div style={styles.hero}>
        <div style={styles.icon}>📄</div>
        <h1 style={styles.h1}>Terms of Service</h1>
        <p style={styles.sub}>Please read these terms carefully before using BirdMap.</p>
      </div>

      <div style={styles.section}>
        <p style={styles.updated}>Last updated: August 2025</p>

        <div style={styles.card}>
          <div style={styles.cardTitle}>1. Data Use</div>
          <div style={styles.cardBody}>Sightings and photos you submit are shared with the BirdMap community to support citizen science research. Location data is stored with each sighting.</div>
        </div>

        <div style={styles.card}>
          <div style={styles.cardTitle}>2. Conduct</div>
          <div style={styles.cardBody}>You agree to submit accurate sightings and not misuse the platform. Spam, offensive content, or intentionally false reports may result in account removal.</div>
        </div>

        <div style={styles.card}>
          <div style={styles.cardTitle}>3. Privacy</div>
          <div style={styles.cardBody}>Your email address is never shared publicly. Your username and sightings are visible to other users.</div>
        </div>

        <div style={styles.card}>
          <div style={styles.cardTitle}>4. Content</div>
          <div style={styles.cardBody}>You retain ownership of photos you upload. By uploading, you grant BirdMap a license to display them within the app.</div>
        </div>

        <div style={styles.card}>
          <div style={styles.cardTitle}>5. Changes</div>
          <div style={styles.cardBody}>These terms may be updated at any time. Continued use of the app constitutes acceptance of the updated terms.</div>
        </div>
      </div>

      <footer style={styles.footer}>© 2025 BirdMap · Citizen Science for Everyone</footer>
    </div>
  )
}
