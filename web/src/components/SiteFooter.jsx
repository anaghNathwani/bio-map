import React from 'react'
import { Link } from 'react-router-dom'
import { ROUTES, SOCIAL_PROFILES } from '../site.js'

// Internal linking: every page links to every other public page (labels come
// from the route registry, so new pages show up here automatically).
export default function SiteFooter() {
  const links = ROUTES.filter(r => r.footerLabel)
  return (
    <footer className="border-t border-[var(--rule)] px-6 py-10 text-[13px] text-[var(--ink-soft)]">
      <div className="mx-auto max-w-5xl">
        <nav aria-label="Footer" className="flex flex-wrap gap-x-6 gap-y-2">
          <Link to="/" className="underline decoration-[var(--rule)] underline-offset-4 hover:text-[var(--ink)]">Home</Link>
          {links.map(r => (
            <Link
              key={r.path}
              to={r.path}
              className="underline decoration-[var(--rule)] underline-offset-4 transition-colors hover:text-[var(--ink)] hover:decoration-[var(--ink)]"
            >
              {r.footerLabel}
            </Link>
          ))}
        </nav>
        {SOCIAL_PROFILES.length > 0 && (
          <nav aria-label="Social profiles" className="mt-3 flex flex-wrap gap-x-6 gap-y-2">
            {SOCIAL_PROFILES.map(url => (
              <a key={url} href={url} rel="me noopener" className="underline decoration-[var(--rule)] underline-offset-4 hover:text-[var(--ink)]">
                {new URL(url).hostname.replace(/^www\./, '')}
              </a>
            ))}
          </nav>
        )}
        <p className="mt-5">© 2026 BirdRadar · Citizen Science</p>
      </div>
    </footer>
  )
}
