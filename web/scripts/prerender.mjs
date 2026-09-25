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
const { ROUTES } = await import(pathToFileURL(path.join(root, 'src/site.js')).href)

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
  write(route.path, template.replace(ROOT_MARKER, `<div id="root">${body}</div>`))
}

// 404.html is what Firebase Hosting serves (with a 404 status) for unknown URLs.
fs.writeFileSync(path.join(dist, '404.html'), template.replace(ROOT_MARKER, `<div id="root">${render('/404')}</div>`))
console.log('prerendered 404.html')
