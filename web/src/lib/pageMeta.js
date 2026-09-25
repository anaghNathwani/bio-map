import { useEffect } from 'react'
import { SITE_NAME, absoluteUrl, routeFor } from '../site.js'

function upsert(selector, tag, attrs) {
  let el = document.head.querySelector(selector)
  if (!el) {
    el = document.createElement(tag)
    document.head.appendChild(el)
  }
  for (const [k, v] of Object.entries(attrs)) el.setAttribute(k, v)
}

/** Applies a route's metadata to <head>. Safe to call repeatedly (client-side navigation). */
export function applyPageMeta(meta) {
  document.title = meta.title
  upsert('meta[name="description"]', 'meta', { name: 'description', content: meta.description })
  upsert('link[rel="canonical"]', 'link', { rel: 'canonical', href: absoluteUrl(meta.path) })
  upsert('meta[name="robots"]', 'meta', { name: 'robots', content: meta.noindex ? 'noindex,follow' : 'index,follow,max-image-preview:large' })
  upsert('meta[property="og:title"]', 'meta', { property: 'og:title', content: meta.title })
  upsert('meta[property="og:description"]', 'meta', { property: 'og:description', content: meta.description })
  upsert('meta[property="og:url"]', 'meta', { property: 'og:url', content: absoluteUrl(meta.path) })
  upsert('meta[property="og:site_name"]', 'meta', { property: 'og:site_name', content: SITE_NAME })
}

/** usePageMeta('/ai') looks the route up in the registry; usePageMeta({ path, title, description }) sets it directly. */
export default function usePageMeta(pathOrMeta) {
  const key = typeof pathOrMeta === 'string' ? pathOrMeta : pathOrMeta.path
  useEffect(() => {
    const meta = typeof pathOrMeta === 'string' ? routeFor(pathOrMeta) : pathOrMeta
    if (meta) applyPageMeta(meta)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])
}
