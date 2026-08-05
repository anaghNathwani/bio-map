import React, { useState, useEffect } from 'react'

const styles = {
  bar: { display: 'flex', gap: 8, alignItems: 'center', flex: 1, maxWidth: 480 },
  input: {
    flex: 1, padding: '6px 12px', borderRadius: 20, border: '1px solid rgba(255,255,255,.2)',
    background: 'rgba(255,255,255,.12)', color: '#fff', fontSize: 13,
    outline: 'none',
  },
  select: {
    padding: '6px 10px', borderRadius: 20, border: '1px solid rgba(255,255,255,.2)',
    background: 'rgba(255,255,255,.12)', color: '#fff', fontSize: 13, cursor: 'pointer',
  },
}

export default function FilterBar({ sightings, onFiltered }) {
  const [species, setSpecies] = useState('')
  const [type, setType] = useState('all')

  useEffect(() => {
    let result = sightings
    if (species.trim()) {
      const q = species.toLowerCase()
      result = result.filter(s =>
        (s.aiSpeciesSuggestion || '').toLowerCase().includes(q) ||
        (s.topSpecies || '').toLowerCase().includes(q) ||
        (s.notes || '').toLowerCase().includes(q)
      )
    }
    if (type !== 'all') {
      result = result.filter(s => s.mediaType === type)
    }
    onFiltered(result)
  }, [sightings, species, type, onFiltered])

  return (
    <div style={styles.bar}>
      <input
        style={styles.input}
        placeholder="Filter by species…"
        value={species}
        onChange={e => setSpecies(e.target.value)}
      />
      <select style={styles.select} value={type} onChange={e => setType(e.target.value)}>
        <option value="all">All types</option>
        <option value="photo">📷 Photo</option>
        <option value="audio">🎙 Audio</option>
      </select>
    </div>
  )
}
