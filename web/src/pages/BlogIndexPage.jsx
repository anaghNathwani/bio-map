import React from 'react'
import { Link } from 'react-router-dom'
import { BookOpen } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'
import { POSTS } from '../content/posts.js'

export default function BlogIndexPage() {
  return (
    <ContentPage
      meta="/blog"
      icon={BookOpen}
      title="BioMap blog"
      intro="Notes on bird identification, on-device AI and citizen science."
    >
      {POSTS.map(post => (
        <article key={post.slug} className="static-page-card">
          <h2 className="static-page-card-title">
            <Link to={`/blog/${post.slug}`} className="underline decoration-[var(--rule)] underline-offset-4 hover:decoration-[var(--ink)]">
              {post.title}
            </Link>
          </h2>
          <p className="static-page-card-body">{post.description}</p>
          <p className="static-page-card-body" style={{ marginTop: 6 }}>
            <time dateTime={post.date}>{post.date}</time>
          </p>
        </article>
      ))}
    </ContentPage>
  )
}
