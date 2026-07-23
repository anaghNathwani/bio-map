import React from 'react'

const styles = {
  overlay: {
    position: 'absolute', top: 16, left: '50%', transform: 'translateX(-50%)',
    zIndex: 2000, width: 320, maxWidth: 'calc(100vw - 32px)',
    background: 'rgba(15,17,23,.95)', backdropFilter: 'blur(12px)',
    borderRadius: 16, border: '1px solid rgba(255,255,255,.1)',
    boxShadow: '0 8px 32px rgba(0,0,0,.5)', overflow: 'hidden',
  },
  photo: { width: '100%', height: 160, objectFit: 'cover', display: 'block' },
  audioPlaceholder: {
    width: '100%', height: 100, background: 'linear-gradient(135deg,#1e1b4b,#312e81)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontSize: 40,
  },
  body: { padding: 14 },
  species: { fontWeight: 700, fontSize: 16, color: '#e2e8f0', marginBottom: 4 },
  meta: { fontSize: 12, color: '#94a3b8', marginBottom: 2 },
  badge: {
    display: 'inline-block', padding: '2px 8px', borderRadius: 10, fontSize: 11,
    fontWeight: 600, marginBottom: 8,
  },
  closeBtn: {
    position: 'absolute', top: 10, right: 10, background: 'rgba(0,0,0,.5)',
    border: 'none', color: '#fff', borderRadius: '50%', width: 28, height: 28,
    cursor: 'pointer', fontSize: 14, display: 'flex', alignItems: 'center', justifyContent: 'center',
  },
  links: { display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' },
  link: {
    fontSize: 11, color: '#38bdf8', textDecoration: 'none', padding: '3px 8px',
    background: 'rgba(56,189,248,.1)', borderRadius: 8, border: '1px solid rgba(56,189,248,.2)',
  },
}

function speciesName(s) {
  return s.top_species || s.ai_species_suggestion || 'Unknown bird'
}

function ebirUrl(species) {
  return `https://ebird.org/search?q=${encodeURIComponent(species)}`
}
function wikiUrl(species) {
  return `https://en.wikipedia.org/wiki/${encodeURIComponent(species.replace(/ /g, '_'))}`
}
function aabUrl(species) {
  return `https://www.allaboutbirds.org/guide/${encodeURIComponent(species.replace(/ /g, '_'))}`
}

export default function SightingPopup({ sighting: s, onClose }) {
  const name = speciesName(s)
  const isAudio = s.media_type === 'audio'
  const conf = s.ai_confidence ? Math.round(s.ai_confidence * 100) : null

  return (
    <div style={styles.overlay}>
      <button style={styles.closeBtn} onClick={onClose}>✕</button>

      {isAudio ? (
        <div style={styles.audioPlaceholder}>🎙️</div>
      ) : s.thumbnail_url || s.photo_url ? (
        <img src={s.thumbnail_url || s.photo_url} alt={name} style={styles.photo} />
      ) : (
        <div style={styles.audioPlaceholder}>🐦</div>
      )}

      {isAudio && s.audio_url && (
        <audio controls style={{ width: '100%', marginTop: 0 }}>
          <source src={s.audio_url} />
        </audio>
      )}

      <div style={styles.body}>
        <div style={styles.species}>{name}</div>

        <span style={{ ...styles.badge, background: isAudio ? 'rgba(139,92,246,.2)' : 'rgba(13,148,136,.2)', color: isAudio ? '#a78bfa' : '#2dd4bf' }}>
          {isAudio ? '🎙 Audio' : '📷 Photo'}
        </span>

        {conf && <div style={styles.meta}>AI confidence: {conf}%</div>}
        <div style={styles.meta}>📍 {s.latitude.toFixed(4)}, {s.longitude.toFixed(4)}</div>
        {s.annotation_count > 0 && (
          <div style={styles.meta}>💬 {s.annotation_count} annotation{s.annotation_count !== 1 ? 's' : ''}</div>
        )}
        {s.notes && <div style={{ ...styles.meta, marginTop: 6, fontStyle: 'italic' }}>"{s.notes}"</div>}

        {name !== 'Unknown bird' && (
          <div style={styles.links}>
            <a href={wikiUrl(name)} target="_blank" rel="noreferrer" style={styles.link}>Wikipedia</a>
            <a href={ebirUrl(name)} target="_blank" rel="noreferrer" style={styles.link}>eBird</a>
            <a href={aabUrl(name)} target="_blank" rel="noreferrer" style={styles.link}>AllAboutBirds</a>
          </div>
        )}
      </div>
    </div>
  )
}
