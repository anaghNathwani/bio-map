import React, { useState, useEffect } from 'react'
import './FilterBar.css'

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
    <div className="filter-bar">
      <input
        className="filter-bar-input"
        placeholder="Filter by species…"
        value={species}
        onChange={e => setSpecies(e.target.value)}
      />
      <select className="filter-bar-select" value={type} onChange={e => setType(e.target.value)}>
        <option value="all">All types</option>
        <option value="photo">📷 Photo</option>
        <option value="audio">🎙 Audio</option>
      </select>
    </div>
  )
}
