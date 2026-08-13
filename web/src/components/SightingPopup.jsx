import React from 'react'
import './SightingPopup.css'

function speciesName(s) {
  return s.topSpecies || s.aiSpeciesSuggestion || 'Unknown bird'
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
  const isAudio = s.mediaType === 'audio'
  const conf = s.aiConfidence ? Math.round(s.aiConfidence * 100) : null

  return (
    <div className="sighting-popup">
      <button className="sighting-popup-close-btn" onClick={onClose}>✕</button>

      {isAudio ? (
        <div className="sighting-popup-audio-placeholder">🎙️</div>
      ) : s.thumbnailURL || s.photoURL ? (
        <img src={s.thumbnailURL || s.photoURL} alt={name} className="sighting-popup-photo" />
      ) : (
        <div className="sighting-popup-audio-placeholder">🐦</div>
      )}

      {isAudio && s.audioURL && (
        <audio controls className="sighting-popup-audio-player">
          <source src={s.audioURL} />
        </audio>
      )}

      <div className="sighting-popup-body">
        <div className="sighting-popup-species">{name}</div>

        <span className={`sighting-popup-badge ${isAudio ? 'sighting-popup-badge--audio' : 'sighting-popup-badge--photo'}`}>
          {isAudio ? '🎙 Audio' : '📷 Photo'}
        </span>

        {conf && <div className="sighting-popup-meta">AI confidence: {conf}%</div>}
        <div className="sighting-popup-meta">📍 {s.latitude.toFixed(4)}, {s.longitude.toFixed(4)}</div>
        {s.annotationCount > 0 && (
          <div className="sighting-popup-meta">💬 {s.annotationCount} annotation{s.annotationCount !== 1 ? 's' : ''}</div>
        )}
        {s.notes && <div className="sighting-popup-meta sighting-popup-meta--notes">"{s.notes}"</div>}

        {name !== 'Unknown bird' && (
          <div className="sighting-popup-links">
            <a href={wikiUrl(name)} target="_blank" rel="noreferrer" className="sighting-popup-link">Wikipedia</a>
            <a href={ebirUrl(name)} target="_blank" rel="noreferrer" className="sighting-popup-link">eBird</a>
            <a href={aabUrl(name)} target="_blank" rel="noreferrer" className="sighting-popup-link">AllAboutBirds</a>
          </div>
        )}
      </div>
    </div>
  )
}
