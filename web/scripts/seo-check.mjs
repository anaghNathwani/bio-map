// Lints the BUILT site (dist/) for the basics Google cares about.
// Usage: npm run build && npm run seo:check   (exit code 1 on any failure)
import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const root = path.resolve(import.meta.dirname, '..')
const dist = path.join(root, 'dist')
const { ROUTES, absoluteUrl } = await import(pathToFileURL(path.join(root, 'src/site.js')).href)

const problems = []
const fail = (where, msg) => problems.push(`${where}: ${msg}`)
const fileFor = p => path.join(dist, p === '/' ? 'index.html' : p.replace(/^\//, '') + '.html')
const attr = (html, re) => (html.match(re) || [])[1]
const seen = { title: new Map(), description: new Map() }

for (const route of ROUTES) {
  const where = route.path
  const file = fileFor(route.path)
  if (!fs.existsSync(file)) { fail(where, 'no built file ' + path.relative(root, file)); continue }
  const html = fs.readFileSync(file, 'utf8')

  const title = attr(html, /<title>([\s\S]*?)<\/title>/)
  const desc = attr(html, /<meta name="description" content="([^"]*)"/)
  if (!title) fail(where, 'missing <title>')
  else if (title.length < 10 || title.length > 65) fail(where, `title length ${title.length} (want 10-65)`)
  if (!desc) fail(where, 'missing meta description')
  else if (desc.length < 70 || desc.length > 170) fail(where, `description length ${desc.length} (want 70-170)`)
  for (const [k, v] of [['title', title], ['description', desc]]) {
    if (v && seen[k].has(v)) fail(where, `duplicate ${k} (also on ${seen[k].get(v)})`)
    else if (v) seen[k].set(v, where)
  }

  const canonical = attr(html, /<link rel="canonical" href="([^"]*)"/)
  if (canonical !== absoluteUrl(route.path)) fail(where, `canonical is ${canonical}, want ${absoluteUrl(route.path)}`)
  if (!/<html lang="[a-z-]+"/.test(html)) fail(where, 'missing <html lang>')
  if (!/<meta name="viewport"/.test(html)) fail(where, 'missing viewport meta')
  for (const p of ['og:title', 'og:description', 'og:url', 'og:image']) {
    if (!html.includes(`property="${p}"`)) fail(where, 'missing ' + p)
  }
  const h1s = (html.match(/<h1[\s>]/g) || []).length
  if (h1s !== 1) fail(where, `${h1s} <h1> elements (want exactly 1)`)
  if (route.prerender && /<div id="root"><\/div>/.test(html)) fail(where, 'prerendered page has an empty #root')
}

if (!fs.existsSync(path.join(dist, '404.html'))) fail('404.html', 'missing')
const sitemap = fs.existsSync(path.join(dist, 'sitemap.xml')) ? fs.readFileSync(path.join(dist, 'sitemap.xml'), 'utf8') : ''
for (const r of ROUTES.filter(r => !r.noindex)) {
  if (!sitemap.includes(`<loc>${absoluteUrl(r.path)}</loc>`)) fail('sitemap.xml', 'missing ' + r.path)
}

// Every internal link on every built page must point at a real file.
function htmlFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e =>
    e.isDirectory() ? (e.name === 'assets' ? [] : htmlFiles(path.join(dir, e.name))) : e.name.endsWith('.html') ? [path.join(dir, e.name)] : []
  )
}
for (const file of htmlFiles(dist)) {
  const html = fs.readFileSync(file, 'utf8')
  for (const [, href] of html.matchAll(/<a [^>]*href="([^"]+)"/g)) {
    if (!href.startsWith('/') || href.startsWith('//')) continue // external, mailto, #anchor
    const clean = href.split('#')[0].split('?')[0]
    const target = clean === '/' ? 'index.html' : clean.replace(/^\//, '')
    const ok = [target, target + '.html'].some(t => fs.existsSync(path.join(dist, t)) && fs.statSync(path.join(dist, t)).isFile())
    if (!ok) fail(path.relative(dist, file), `broken internal link ${href}`)
  }
}

if (problems.length) {
  console.error('SEO check failed:\n - ' + problems.join('\n - '))
  process.exit(1)
}
console.log(`SEO check passed for ${ROUTES.length} pages.`)
