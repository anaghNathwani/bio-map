// Tells Bing, Yandex and other IndexNow engines which URLs changed (Google does not
// use IndexNow; it uses Search Console + the sitemap). Free, no account needed.
//   node scripts/indexnow.mjs            -> dry run, prints what would be sent
//   node scripts/indexnow.mjs --submit   -> sends it (run AFTER deploying)
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const KEY = '62259ef729e05ae65a5f78ca64f5e490' // also served at /62259ef729e05ae65a5f78ca64f5e490.txt so engines can verify ownership
const root = path.resolve(import.meta.dirname, '..')
const { ROUTES, SITE_URL, absoluteUrl } = await import(pathToFileURL(path.join(root, 'src/site.js')).href)

const urlList = ROUTES.filter(r => !r.noindex).map(r => absoluteUrl(r.path))
const body = { host: new URL(SITE_URL).host, key: KEY, keyLocation: `${SITE_URL}/${KEY}.txt`, urlList }

if (!process.argv.includes('--submit')) {
  console.log('Dry run. Would submit:\n' + JSON.stringify(body, null, 2))
  process.exit(0)
}
const res = await fetch('https://api.indexnow.org/indexnow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify(body),
})
console.log('IndexNow responded', res.status, res.statusText)
process.exit(res.ok ? 0 : 1)
