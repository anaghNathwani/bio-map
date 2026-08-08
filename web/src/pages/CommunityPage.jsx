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
  steps: { listStyle: 'none', padding: 0, margin: '0 0 32px' },
  step: {
    display: 'flex', gap: 16, marginBottom: 20,
    background: 'rgba(255,255,255,.05)', border: '1px solid rgba(255,255,255,.08)',
    borderRadius: 12, padding: '18px 20px',
  },
  stepNum: {
    width: 32, height: 32, borderRadius: '50%', background: '#0d9488',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontWeight: 700, fontSize: 14, flexShrink: 0, color: '#fff',
  },
  stepText: { flex: 1 },
  stepTitle: { fontWeight: 600, fontSize: 15, color: '#fff', marginBottom: 4 },
  stepBody: { fontSize: 14, color: '#94a3b8', lineHeight: 1.6 },
  footer: { textAlign: 'center', padding: '24px', color: '#475569', fontSize: 13, borderTop: '1px solid rgba(255,255,255,.06)' },
}

export default function CommunityPage() {
  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <a href="/" style={styles.back}>← Map</a>
        <span style={styles.logo}>🐦 BirdMap</span>
      </header>

      <div style={styles.hero}>
        <div style={styles.icon}>👥</div>
        <h1 style={styles.h1}>Community Annotations</h1>
        <p style={styles.sub}>
          Every sighting on BirdMap can be reviewed and verified by the community,
          making the data more accurate over time.
        </p>
      </div>

      <div style={styles.section}>
        <h2 style={styles.h2}>How annotations work</h2>
        <p style={styles.p}>
          When you or another user submits a sighting, the community can open it and
          add an annotation — confirming or correcting the species, describing
          behaviour, and assigning a confidence level. Multiple annotations on the
          same sighting create a consensus that improves data quality for everyone.
        </p>

        <h2 style={styles.h2}>The annotation process</h2>
        <ul style={styles.steps}>
          <li style={styles.step}>
            <div style={styles.stepNum}>1</div>
            <div style={styles.stepText}>
              <div style={styles.stepTitle}>Browse the map</div>
              <div style={styles.stepBody}>Tap any marker on the BirdMap community map to open a sighting — photo or audio.</div>
            </div>
          </li>
          <li style={styles.step}>
            <div style={styles.stepNum}>2</div>
            <div style={styles.stepText}>
              <div style={styles.stepTitle}>Review the evidence</div>
              <div style={styles.stepBody}>Look at the photo or listen to the recording, and note the AI's suggested species identification.</div>
            </div>
          </li>
          <li style={styles.step}>
            <div style={styles.stepNum}>3</div>
            <div style={styles.stepText}>
              <div style={styles.stepTitle}>Add your annotation</div>
              <div style={styles.stepBody}>Confirm or correct the species, note the behaviour you observe, and set your confidence level (low / medium / high).</div>
            </div>
          </li>
          <li style={styles.step}>
            <div style={styles.stepNum}>4</div>
            <div style={styles.stepText}>
              <div style={styles.stepTitle}>Earn leaderboard points</div>
              <div style={styles.stepBody}>Each annotation earns you a point on the community leaderboard, recognising your contribution to the science.</div>
            </div>
          </li>
        </ul>

        <h2 style={styles.h2}>Why it matters</h2>
        <p style={styles.p}>
          AI models are not perfect. Community review catches misidentifications,
          adds behavioural context that photos alone can't convey, and builds a
          layer of human expertise on top of automated suggestions. Over time, your
          annotations also feed back into model retraining — so the AI improves
          because of you.
        </p>
      </div>

      <footer style={styles.footer}>© 2026 BirdMap · Citizen Science</footer>
    </div>
  )
}
