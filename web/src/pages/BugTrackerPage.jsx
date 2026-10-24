import React, { useEffect, useState } from 'react'
import BlogShell from '../components/BlogShell.jsx'

const fmtDate = ms => (ms ? new Date(ms).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : '—')

function turnaround(b) {
  if (!b.fixedAt || !b.reportedAt) return '—'
  const hours = Math.max(0, (b.fixedAt - b.reportedAt) / 36e5)
  return hours < 48 ? `${Math.round(hours)} h` : `${Math.round(hours / 24)} days`
}

const status = b => (b.fixedAt ? 'Fixed' : b.notedAt ? 'Noted' : 'Reported')

export default function BugTrackerPage() {
  const [rows, setRows] = useState(null)
  const [error, setError] = useState(false)

  useEffect(() => {
    let live = true
    import('../firebase.js')
      .then(m => m.fetchBugTracker())
      .then(r => live && setRows(r))
      .catch(() => live && setError(true))
    return () => { live = false }
  }, [])

  return (
    <BlogShell meta="/blog/bug-tracker">
      <h1 className="static-page-h1">Bug tracker</h1>
      <p className="static-page-sub">Bugs reported from the BioMap beta, when we noted them, when they were fixed, and how long that took.</p>
      {error && <p className="static-page-card-body">The tracker could not be loaded right now. Please try again later.</p>}
      {!error && rows === null && <p className="static-page-card-body">Loading…</p>}
      {rows && rows.length === 0 && <p className="static-page-card-body">No bugs reported yet.</p>}
      {rows && rows.length > 0 && (
        <div className="bug-table-wrap">
          <table className="bug-table">
            <thead>
              <tr><th>Bug</th><th>Status</th><th>Reported</th><th>Noted</th><th>Fixed</th><th>Turnaround</th></tr>
            </thead>
            <tbody>
              {rows.map(b => (
                <tr key={b.id}>
                  <td>{b.title}{b.appVersion && b.appVersion !== 'unknown' ? <span className="bug-ver"> · v{b.appVersion}</span> : null}</td>
                  <td><span className={`bug-status bug-status-${status(b).toLowerCase()}`}>{status(b)}</span></td>
                  <td>{fmtDate(b.reportedAt)}</td>
                  <td>{fmtDate(b.notedAt)}</td>
                  <td>{fmtDate(b.fixedAt)}</td>
                  <td>{turnaround(b)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </BlogShell>
  )
}
