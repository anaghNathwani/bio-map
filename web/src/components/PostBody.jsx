import React from 'react'

/** Renders the block array from content/posts.js. */
export default function PostBody({ blocks }) {
  return blocks.map((b, i) => {
    if (b.h2) return <h2 key={i} className="static-page-h2">{b.h2}</h2>
    if (b.ul) {
      return (
        <ul key={i} className="static-page-p" style={{ paddingLeft: 20, listStyle: 'disc' }}>
          {b.ul.map(li => <li key={li}>{li}</li>)}
        </ul>
      )
    }
    return <p key={i} className="static-page-p">{b.p}</p>
  })
}
