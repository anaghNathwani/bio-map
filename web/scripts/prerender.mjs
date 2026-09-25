// Build-time prerender: turns the client build (dist/) into real per-page HTML
// so crawlers and no-JS visitors get content, not an empty <div id="root">.
// Run after: vite build && vite build --ssr src/entry-server.jsx --outDir dist-ssr
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const root = path.resolve(import.meta.dirname, '..')
const dist = path.join(root, 'dist')
const template = fs.readFileSync(path.join(dist, 'index.html'), 'utf8')
const { render } = await import(pathToFileURL(path.join(root, 'dist-ssr/entry-server.js')).href)
const { ROUTES, SITE_NAME, absoluteUrl, jsonLdFor } = await import(pathToFileURL(path.join(root, 'src/site.js')).href)
const { NOT_FOUND_META } = await import(pathToFileURL(path.join(root, 'src/notFoundMeta.js')).href)

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;')

// Swap one existing tag for a route-specific one; fail the build if the tag is
// missing from index.html rather than silently shipping the wrong metadata.
function swap(html, pattern, replacement) {
  if (!pattern.test(html)) throw new Error('index.html has no tag matching ' + pattern)
  return html.replace(pattern, replacement)
}

const NOSCRIPT = /\s*<noscript>[\s\S]*?<\/noscript>/

/** Full per-page <head>: title, description, canonical, robots, OG, Twitter, JSON-LD. */
function applyHead(html, meta, { keepNoscript }) {
  const url = absoluteUrl(meta.path)
  const robots = meta.noindex ? 'noindex,follow' : 'index,follow,max-image-preview:large'
  html = swap(html, /<title>[\s\S]*?<\/title>/, `<title>${esc(meta.title)}</title>`)
  html = swap(html, /<meta name="description"[^>]*>/, `<meta name="description" content="${esc(meta.description)}" />`)
  html = swap(html, /<meta name="robots"[^>]*>/, `<meta name="robots" content="${robots}" />`)
  html = swap(html, /<link rel="canonical"[^>]*>/, `<link rel="canonical" href="${url}" />`)
  html = swap(html, /<meta property="og:title"[^>]*>/, `<meta property="og:title" content="${esc(meta.title)}" />`)
  html = swap(html, /<meta property="og:description"[^>]*>/, `<meta property="og:description" content="${esc(meta.description)}" />`)
  html = swap(html, /<meta property="og:url"[^>]*>/, `<meta property="og:url" content="${url}" />`)
  html = swap(html, /<meta name="twitter:title"[^>]*>/, `<meta name="twitter:title" content="${esc(meta.title)}" />`)
  html = swap(html, /<meta name="twitter:description"[^>]*>/, `<meta name="twitter:description" content="${esc(meta.description)}" />`)
  const ld = jsonLdFor(meta)
    .map(o => `    <script type="application/ld+json" data-seo="jsonld">${JSON.stringify(o).replace(/</g, '\\u003c')}</script>\n`)
    .join('')
  html = html.replace('</head>', ld + '  </head>')
  // The <noscript> block is only useful where #root is empty (the map shell).
  if (!keepNoscript) html = html.replace(NOSCRIPT, '')
  return html
}

const ROOT_MARKER = '<div id="root"></div>'
if (!template.includes(ROOT_MARKER)) throw new Error('index.html is missing ' + ROOT_MARKER)

function outFile(routePath) {
  return routePath === '/' ? 'index.html' : routePath.replace(/^\//, '') + '.html'
}

function write(routePath, html) {
  const file = path.join(dist, outFile(routePath))
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, html)
  console.log('prerendered', routePath, '->', path.relative(root, file))
}

for (const route of ROUTES) {
  const body = route.prerender ? render(route.path) : ''
  const html = template.replace(ROOT_MARKER, `<div id="root">${body}</div>`)
  write(route.path, applyHead(html, route, { keepNoscript: !route.prerender }))
}

// 404.html is what Firebase Hosting serves (with a 404 status) for unknown URLs.
fs.writeFileSync(
  path.join(dist, '404.html'),
  applyHead(template.replace(ROOT_MARKER, `<div id="root">${render('/404')}</div>`), NOT_FOUND_META, { keepNoscript: false })
)
console.log('prerendered 404.html')
