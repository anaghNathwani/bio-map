import React from 'react'
import { Link } from 'react-router-dom'
import BlogShell from '../components/BlogShell.jsx'
import { POSTS } from '../content/posts.js'

function PostList({ heading, posts }) {
  if (posts.length === 0) return null
  return (
    <section>
      <h2 className="blog-sidebar-heading" style={{ marginTop: 28 }}>{heading}</h2>
      {posts.map(post => (
        <article key={post.slug} className="static-page-card">
          <h3 className="static-page-card-title">
            <Link to={`/blog/${post.slug}`} className="underline decoration-[var(--rule)] underline-offset-4 hover:decoration-[var(--fg)]">
              {post.title}
            </Link>
          </h3>
          <p className="static-page-card-body">{post.description}</p>
          {post.date && (
            <p className="static-page-card-body" style={{ marginTop: 6 }}>
              <time dateTime={post.date}>{post.date}</time>
            </p>
          )}
        </article>
      ))}
    </section>
  )
}

export default function BlogIndexPage() {
  return (
    <BlogShell meta="/blog">
      <h1 className="static-page-h1">BioMap blog</h1>
      <p className="static-page-sub">Notes on bird identification, on-device AI and citizen science.</p>
      <PostList heading="Important" posts={[...POSTS.filter(p => p.pinned), { slug: 'bug-tracker', title: 'Bug tracker', description: 'Bugs reported from the beta, when they were noted and fixed, and the turnaround time.' }]} />
      <PostList heading="General" posts={POSTS.filter(p => !p.pinned)} />
    </BlogShell>
  )
}
