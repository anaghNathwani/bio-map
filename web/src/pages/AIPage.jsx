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
  highlight: {
    background: 'rgba(13,148,136,.12)', border: '1px solid rgba(13,148,136,.3)',
    borderRadius: 10, padding: '20px 24px', marginBottom: 32,
    fontSize: 15, color: '#5eead4', lineHeight: 1.7,
  },
  footer: { textAlign: 'center', padding: '24px', color: '#475569', fontSize: 13, borderTop: '1px solid rgba(255,255,255,.06)' },
}

export default function AIPage() {
  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <a href="/" style={styles.back}>← Map</a>
        <span style={styles.logo}>🐦 BirdMap</span>
      </header>

      <div style={styles.hero}>
        <div style={styles.icon}>✨</div>
        <h1 style={styles.h1}>On-Device AI Identification</h1>
        <p style={styles.sub}>
          BirdMap identifies birds instantly from your photos — entirely on your
          device, with no photo sent to a server before you choose to share it.
        </p>
      </div>

      <div style={styles.section}>
        <h2 style={styles.h2}>How it works</h2>
        <p style={styles.p}>
          When you take a photo in the BirdMap app, a CoreML model runs directly
          on your iPhone's Neural Engine. Within seconds it returns a ranked list
          of likely species. You see the top suggestion immediately — no internet
          connection required for the identification itself.
        </p>

        <div style={styles.highlight}>
          🔒 Your photo never leaves your device until you tap <strong>Submit</strong>.
          Identification happens locally, keeping your privacy intact.
        </div>

        <h2 style={styles.h2}>The model</h2>

        <div style={styles.card}>
          <div style={styles.cardTitle}>Architecture</div>
          <div style={styles.cardBody}>EfficientNet-B0 fine-tuned on community-submitted sightings and exported to Apple's CoreML format (.mlpackage) for fast, low-power inference on-device.</div>
        </div>
        <div style={styles.card}>
          <div style={styles.cardTitle}>Self-improving</div>
          <div style={styles.cardBody}>Community annotations feed a retraining pipeline. When enough new verified sightings accumulate, a new model version is built and silently delivered to the app — so accuracy improves over time.</div>
        </div>
        <div style={styles.card}>
          <div style={styles.cardTitle}>Over-the-air updates</div>
          <div style={styles.cardBody}>The app checks for a newer model version on launch. If one is available, it downloads in the background and is ready for your next sighting — no App Store update needed.</div>
        </div>

        <h2 style={styles.h2}>Limitations</h2>
        <p style={styles.p}>
          The model performs best on clear, well-lit photos where the bird is the
          main subject. Distant, blurry, or partially obscured birds may yield lower
          confidence scores or incorrect suggestions. That's why community
          annotation exists — human expertise corrects what AI gets wrong, and those
          corrections make the next model better.
        </p>
      </div>

      <footer style={styles.footer}>© 2026 BirdMap · Citizen Science</footer>
    </div>
  )
}
