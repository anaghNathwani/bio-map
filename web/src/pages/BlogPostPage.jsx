import React from 'react'
import { useParams } from 'react-router-dom'
import BlogShell from '../components/BlogShell.jsx'
import PostBody from '../components/PostBody.jsx'
import RelatedLinks from '../components/RelatedLinks.jsx'
import NotFoundPage from './NotFoundPage.jsx'
import { ROUTES, relatedFor } from '../site.js'

export default function BlogPostPage() {
  const { slug } = useParams()
  const meta = ROUTES.find(r => r.path === `/blog/${slug}`)
  if (!meta) return <NotFoundPage />
  const { post } = meta
  return (
    <BlogShell meta={meta}>
      <h1 className="static-page-h1">{post.title}</h1>
      <p className="static-page-sub">{post.description}</p>
      <p className="static-page-card-body" style={{ marginBottom: 24 }}>
        Published <time dateTime={post.date}>{post.date}</time>
      </p>
      <PostBody blocks={post.body} />
      <RelatedLinks paths={relatedFor(meta)} />
    </BlogShell>
  )
}
