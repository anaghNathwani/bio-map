import React from 'react'
import { Link, NavLink } from 'react-router-dom'
import { BookOpen } from 'lucide-react'
import StaticPageHeader from './StaticPageHeader.jsx'
import SiteFooter from './SiteFooter.jsx'
import usePageMeta from '../lib/pageMeta.js'
import { POSTS } from '../content/posts.js'
import '../pages/StaticPage.css'
import '../pages/BlogShell.css'

const SECTIONS = [
  {
    label: 'Important',
    posts: [...POSTS.filter(p => p.pinned), { slug: 'bug-tracker', title: 'Bug tracker' }],
  },
  { label: 'General', posts: POSTS.filter(p => !p.pinned) },
]

/** Blog-only layout: left vertical nav (Important = pinned posts, General = the rest) plus content. */
export default function BlogShell({ meta, children }) {
  usePageMeta(meta)
  return (
    <div className="static-page">
      <StaticPageHeader />
      <div className="blog-shell">
        <aside className="blog-sidebar">
          <nav aria-label="Blog">
            <Link to="/blog" className="blog-sidebar-home"><BookOpen size={15} strokeWidth={1.75} />All posts</Link>
            {SECTIONS.map(section => (
              <div key={section.label} className="blog-sidebar-group">
                <h2 className="blog-sidebar-heading">{section.label}</h2>
                {section.posts.length === 0 ? (
                  <p className="blog-sidebar-empty">Nothing here yet.</p>
                ) : (
                  <ul>
                    {section.posts.map(post => (
                      <li key={post.slug}>
                        <NavLink to={`/blog/${post.slug}`} className="blog-sidebar-link">{post.title}</NavLink>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            ))}
          </nav>
        </aside>
        <main id="main" className="blog-main">{children}</main>
      </div>
      <SiteFooter />
    </div>
  )
}
