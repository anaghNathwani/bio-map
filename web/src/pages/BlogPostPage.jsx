import React from 'react'
import { useParams } from 'react-router-dom'
import { BookOpen } from 'lucide-react'
import ContentPage from '../components/ContentPage.jsx'
import PostBody from '../components/PostBody.jsx'
import NotFoundPage from './NotFoundPage.jsx'
import { ROUTES } from '../site.js'

export default function BlogPostPage() {
  const { slug } = useParams()
  const meta = ROUTES.find(r => r.path === `/blog/${slug}`)
  if (!meta) return <NotFoundPage />
  const { post } = meta
  return (
    <ContentPage meta={meta} icon={BookOpen} title={post.title} intro={post.description}>
      <p className="static-page-card-body" style={{ marginBottom: 24 }}>
        Published <time dateTime={post.date}>{post.date}</time>
      </p>
      <PostBody blocks={post.body} />
    </ContentPage>
  )
}
