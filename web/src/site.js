// Single source of truth for the marketing site's SEO metadata. Read by the
// client (usePageMeta), the prerender script, the sitemap and the seo-check.
export const SITE_URL = 'https://birdmap-citizenscience.web.app'
export const SITE_NAME = 'BirdMap'
export const DEFAULT_DESCRIPTION =
  'BirdMap is a citizen science app and live map for bird sightings. Identify birds from photos and calls on your phone, then let the community verify them.'

/**
 * One entry per public page.
 *  - prerender: true  -> real HTML is generated at build time (static content pages)
 *  - prerender: false -> app shell only (the interactive map), metadata still injected
 */
export const ROUTES = [
  {
    path: '/',
    title: 'BirdMap: Bird Sighting Map & On-Device Bird ID',
    description: DEFAULT_DESCRIPTION,
    changefreq: 'weekly',
    priority: 1.0,
    prerender: true,
  },
  {
    path: '/map',
    title: 'Live Bird Sighting Map | BirdMap',
    description:
      'Explore bird sightings reported by the BirdMap community on a live map. Filter by species and see photo and audio sightings as they come in.',
    changefreq: 'hourly',
    priority: 0.9,
    prerender: false,
    footerLabel: 'Live map',
    breadcrumb: 'Live map',
    jsonLd: [
      {
        '@context': 'https://schema.org',
        '@type': 'WebApplication',
        name: 'BirdMap live sighting map',
        url: SITE_URL + '/map',
        applicationCategory: 'EducationalApplication',
        operatingSystem: 'Any (web browser)',
        description:
          'A live map of bird sightings (photos and audio) reported by the BirdMap community.',
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
        isPartOf: { '@id': SITE_URL + '/#website' },
      },
    ],
  },
  {
    path: '/ai',
    title: 'On-Device Bird Identification AI | BirdMap',
    description:
      'How BirdMap identifies birds from your photos entirely on your phone, which models it uses, and where the limits are.',
    changefreq: 'monthly',
    priority: 0.7,
    prerender: true,
    footerLabel: 'On-device AI',
    breadcrumb: 'On-device AI',
  },
  {
    path: '/community',
    title: 'Community Bird Annotations | BirdMap',
    description:
      'Every BirdMap sighting can be reviewed and confirmed by other birders. See how community annotations build a trustworthy bird dataset.',
    changefreq: 'monthly',
    priority: 0.7,
    prerender: true,
    footerLabel: 'Community',
    breadcrumb: 'Community annotations',
  },
  {
    path: '/citizen-science',
    title: 'Citizen Science Bird Tracking | BirdMap',
    description:
      'Contribute geotagged bird photos and recordings to a shared, growing dataset. Learn how citizen science bird tracking works in BirdMap.',
    changefreq: 'monthly',
    priority: 0.7,
    prerender: true,
    footerLabel: 'Citizen science',
    breadcrumb: 'Citizen science',
  },
  {
    path: '/terms',
    title: 'Terms of Service | BirdMap',
    description: 'The terms that apply when you use BirdMap: data use, conduct, privacy, content and changes.',
    changefreq: 'yearly',
    priority: 0.3,
    prerender: true,
    footerLabel: 'Terms of Service',
    breadcrumb: 'Terms of Service',
  },
]

export const absoluteUrl = path => SITE_URL + (path === '/' ? '/' : path)
export const routeFor = path => ROUTES.find(r => r.path === path)

/** BreadcrumbList for a sub-page: Home > (parent) > page. */
export function breadcrumbLd(meta) {
  if (meta.path === '/') return null
  const trail = [{ name: 'Home', path: '/' }, ...(meta.parents || []), { name: meta.breadcrumb || meta.title, path: meta.path }]
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: trail.map((t, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: t.name,
      item: absoluteUrl(t.path),
    })),
  }
}

/** Every JSON-LD block a page should emit (client hook and prerender share this). */
export function jsonLdFor(meta) {
  const crumbs = breadcrumbLd(meta)
  return [...(meta.jsonLd || []), ...(crumbs ? [crumbs] : [])]
}
