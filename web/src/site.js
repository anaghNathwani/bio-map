import { FAQ } from './content/faq.js'
import { POSTS } from './content/posts.js'

// Single source of truth for the marketing site's SEO metadata. Read by the
// client (usePageMeta), the prerender script, the sitemap and the seo-check.
export const SITE_URL = 'https://birdmap-citizenscience.web.app'
export const SITE_NAME = 'BirdMap'
// Set this to a real inbox and the privacy page shows a contact line. Left empty on purpose.
export const CONTACT_EMAIL = ''
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
  {
    path: '/how-it-works',
    title: 'How BirdMap Works: Photo, Sound & Community ID',
    description:
      'From capturing a bird photo or call to on-device identification and community review: a step-by-step look at how BirdMap works.',
    changefreq: 'monthly',
    priority: 0.8,
    prerender: true,
    breadcrumb: 'How it works',
    footerLabel: 'How it works',
  },
  {
    path: '/faq',
    title: 'BirdMap FAQ: Bird ID, Privacy & How It Works',
    description:
      'Answers to common questions about BirdMap: how bird identification works on your phone, accuracy, privacy, cost and availability.',
    changefreq: 'monthly',
    priority: 0.7,
    prerender: true,
    breadcrumb: 'FAQ',
    footerLabel: 'FAQ',
    jsonLd: [
      {
        '@context': 'https://schema.org',
        '@type': 'FAQPage',
        mainEntity: FAQ.map(item => ({
          '@type': 'Question',
          name: item.q,
          acceptedAnswer: { '@type': 'Answer', text: item.a },
        })),
      },
    ],
  },
  {
    path: '/about',
    title: 'About BirdMap: Citizen Science for Bird Lovers',
    description:
      'BirdMap turns everyday bird sightings into a shared, community-verified dataset. Learn what we are building and the principles behind it.',
    changefreq: 'yearly',
    priority: 0.5,
    prerender: true,
    breadcrumb: 'About',
    footerLabel: 'About',
  },
  {
    path: '/privacy',
    title: 'Privacy Notice | BirdMap',
    description:
      'What BirdMap stores when you use it, who can see it, and how identification on your device keeps photos and recordings private until you share them.',
    changefreq: 'yearly',
    priority: 0.3,
    prerender: true,
    breadcrumb: 'Privacy',
    footerLabel: 'Privacy',
  },
  {
    path: '/bird-sound-identification',
    title: 'Identify Birds by Sound: On-Device BirdNET | BirdMap',
    description:
      'Record a bird call and BirdMap identifies it on your phone with Cornell Lab of Ornithology\u2019s BirdNET, using your location to rule out unlikely species.',
    changefreq: 'monthly',
    priority: 0.8,
    prerender: true,
    breadcrumb: 'Bird sound identification',
    footerLabel: 'Bird sound ID',
  },
  {
    path: '/bird-photo-identification',
    title: 'Identify Birds from a Photo: On-Device AI | BirdMap',
    description:
      'Take or choose a bird photo and BirdMap suggests the species on your phone using Google\u2019s AIY Birds model, with honest confidence and community review.',
    changefreq: 'monthly',
    priority: 0.8,
    prerender: true,
    breadcrumb: 'Bird photo identification',
    footerLabel: 'Bird photo ID',
  },
  {
    path: '/blog',
    title: 'BirdMap Blog: Bird ID, AI and Citizen Science',
    description:
      'Articles on how BirdMap identifies birds on your phone, what citizen science bird data is for, and how to get better sightings.',
    changefreq: 'weekly',
    priority: 0.6,
    prerender: true,
    breadcrumb: 'Blog',
    footerLabel: 'Blog',
  },
  ...POSTS.map(post => ({
    path: `/blog/${post.slug}`,
    title: `${post.title} | BirdMap`,
    description: post.description,
    changefreq: 'yearly',
    priority: 0.6,
    prerender: true,
    breadcrumb: post.title,
    parents: [{ name: 'Blog', path: '/blog' }],
    post,
    jsonLd: [
      {
        '@context': 'https://schema.org',
        '@type': 'BlogPosting',
        headline: post.title,
        description: post.description,
        datePublished: post.date,
        dateModified: post.dateModified || post.date,
        image: SITE_URL + '/og-image.png',
        mainEntityOfPage: `${SITE_URL}/blog/${post.slug}`,
        author: { '@type': 'Organization', name: SITE_NAME, url: SITE_URL + '/' },
        publisher: { '@id': SITE_URL + '/#org' },
        inLanguage: 'en',
      },
    ],
  })),
]

/** Hand-picked cross-links for content pages (blog posts get the other posts + how-it-works). */
export const RELATED = {
  '/how-it-works': ['/bird-photo-identification', '/bird-sound-identification', '/faq'],
  '/faq': ['/how-it-works', '/privacy', '/about'],
  '/about': ['/how-it-works', '/citizen-science', '/community'],
  '/privacy': ['/terms', '/faq'],
  '/bird-sound-identification': ['/bird-photo-identification', '/how-it-works', '/community'],
  '/bird-photo-identification': ['/bird-sound-identification', '/ai', '/how-it-works'],
}

export const absoluteUrl = path => SITE_URL + (path === '/' ? '/' : path)
export const routeFor = path => ROUTES.find(r => r.path === path)

export function relatedFor(meta) {
  if (RELATED[meta.path]) return RELATED[meta.path]
  if (meta.post) {
    return [...POSTS.filter(p => p.slug !== meta.post.slug).map(p => `/blog/${p.slug}`), '/how-it-works'].slice(0, 3)
  }
  return []
}

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
