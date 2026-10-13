import React from 'react'
import { Link } from 'react-router-dom'
import { routeFor } from '../site.js'

/** "Keep reading" links between content pages: helps visitors and crawlers. */
export default function RelatedLinks({ paths }) {
  const items = paths.map(routeFor).filter(Boolean)
  if (!items.length) return null
  return (
    <nav aria-label="Related pages" style={{ marginTop: 40 }}>
      <h2 className="static-page-h2">Keep reading</h2>
      <ul style={{ paddingLeft: 0, listStyle: 'none' }}>
        {items.map(r => (
          <li key={r.path} className="static-page-card">
            <Link to={r.path} className="static-page-card-title underline decoration-[var(--rule)] underline-offset-4 hover:decoration-[var(--fg)]">
              {r.breadcrumb || r.title}
            </Link>
            <p className="static-page-card-body">{r.description}</p>
          </li>
        ))}
      </ul>
    </nav>
  )
}
