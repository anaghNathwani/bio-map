import React from 'react'
import { Link } from 'react-router-dom'
import WaitlistButton from '../components/WaitlistButton.jsx'
import WaitlistForm from '../components/WaitlistForm.jsx'
import BioLoader from '../components/BioLoader.jsx'
import NameStoryLink from '../components/NameStory.jsx'
import { FAQ } from '../content/faq.js'
import SiteFooter from '../components/SiteFooter.jsx'
import ThemeToggle from '../components/ThemeToggle.jsx'
import birdMark from '../assets/bird-mark.svg'
import usePageMeta from '../lib/pageMeta.js'

const FEATURES = [
  {
    href: '/ai',
    title: 'On-device AI.',
    body: 'A model on your phone identifies species from your photos in seconds. Nothing leaves your device until you choose to share it.',
  },
  {
    href: '/community',
    title: 'Community annotation.',
    body: 'Every sighting can be reviewed and confirmed by other birders, building a consensus that keeps improving with every visit.',
  },
  {
    href: '/citizen-science',
    title: 'Citizen science.',
    body: 'Your sightings feed a shared, growing dataset, geotagged and timestamped, that researchers and conservationists can rely on.',
  },
  {
    href: '/map',
    title: 'Live sighting map.',
    body: 'Photo and audio sightings from the whole community, plotted in real time as they come in.',
  },
]

const FAQ_TEASER = [
  'Is BioMap free?',
  'Where can I get the app?',
  'Do I need an internet connection to identify a bird?',
  'Who can see my photos and location?',
].map(q => FAQ.find(item => item.q === q)).filter(Boolean)

const NAV = [
  { to: '/ai', label: 'AI' },
  { to: '/community', label: 'Community' },
  { to: '/citizen-science', label: 'Citizen Science' },
  { to: '/faq', label: 'FAQ' },
]

export default function LandingPage() {
  usePageMeta('/')
  return (
    <div className="min-h-screen bg-[var(--bg)] font-sans text-[var(--fg)] antialiased selection:bg-[var(--accent-soft)]">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-[60] focus:rounded-lg focus:bg-[var(--fg)] focus:px-3 focus:py-2 focus:text-[var(--bg)]">Skip to content</a>

      {/* Global nav */}
      <header className="nav-bar sticky top-0 z-50 border-b border-[var(--rule)]/60">
        <div className="mx-auto flex h-12 max-w-[980px] items-center gap-6 px-5">
          <Link to="/" aria-label="BioMap home" className="flex items-center gap-2">
            <img src={birdMark} alt="" width="20" height="20" className="bird-logo h-5 w-5" />
            <span className="text-[15px] font-semibold tracking-tight">BioMap</span>
          </Link>
          <nav aria-label="Primary" className="ml-auto hidden items-center gap-7 text-[12px] text-[var(--fg-soft)] sm:flex">
            {NAV.map(item => (
              <Link key={item.to} to={item.to} className="transition-colors hover:text-[var(--fg)]">
                {item.label}
              </Link>
            ))}
          </nav>
          <ThemeToggle className="ml-auto sm:ml-0" />
          <a href="#waitlist" className="btn-blue shrink-0 px-3.5 py-1 text-[12px]">Join the waitlist</a>
        </div>
      </header>

      <main id="main">
        {/* Hero */}
        <section className="mx-auto max-w-[980px] px-5 pb-10 pt-16 text-center md:pt-24">
          <p className="text-[19px] font-semibold text-[var(--fg-soft)] md:text-[21px]">
            Citizen science, one sighting at a time.
          </p>
          <h1 className="mx-auto mt-3 max-w-[820px] text-[44px] font-semibold leading-[1.07] tracking-[-0.03em] sm:text-[60px] md:text-[80px] md:leading-[1.05]">
            Every bird you see becomes data that matters.
          </h1>
          <p className="mx-auto mt-5 max-w-[600px] text-[19px] leading-[1.4] tracking-[-0.01em] text-[var(--fg-soft)] md:text-[24px]">
            Snap a photo or record a call. The community verifies it, and a live map of the whole flock takes shape.
          </p>
          <div className="mt-8 flex flex-wrap items-center justify-center gap-x-8 gap-y-4 text-[19px] md:text-[21px]">
            <a href="#waitlist" className="btn-blue px-6 py-2.5 text-[17px]">Join the waitlist</a>
            <Link to="/map" className="link-chevron">Open the live map</Link>
          </div>
          <p className="mt-6 text-[17px]"><NameStoryLink /></p>
        </section>

        <section className="mx-auto max-w-[1080px] px-5 pb-20 pt-6">
          <div className="tile flex min-h-[340px] items-center justify-center py-14 md:min-h-[460px]" aria-hidden="true">
            <BioLoader size={260} />
          </div>
        </section>

        {/* Statement */}
        <section className="mx-auto max-w-[980px] px-5 pb-28 pt-8 text-center">
          <p className="mx-auto max-w-[760px] text-[28px] font-semibold leading-[1.18] tracking-[-0.02em] md:text-[40px]">
            BioMap turns everyday bird sightings into a living, self-improving dataset. Identified on-device, verified by a community, and mapped for everyone.
          </p>
          <p className="mx-auto mt-6 max-w-[640px] text-[17px] leading-[1.5] text-[var(--fg-soft)]">
            Photos are classified locally by a model built on Google&rsquo;s AIY Birds. Audio recordings
            are matched against Cornell&rsquo;s BirdNET. Every result can be confirmed or corrected by
            other birders, sharpening the consensus each time someone looks up.
          </p>
        </section>

        {/* Features */}
        <section className="bg-[var(--bg-raised)] py-20 md:py-28">
          <div className="mx-auto max-w-[1080px] px-5">
            <h2 className="text-center text-[32px] font-semibold tracking-[-0.025em] md:text-[48px]">How it fits together.</h2>
            <div className="mt-12 grid gap-5 md:grid-cols-2">
              {FEATURES.map(f => (
                <Link key={f.href} to={f.href} className="group flex min-h-[260px] flex-col rounded-[28px] bg-[var(--bg)] p-8 md:p-10">
                  <h3 className="text-[28px] font-semibold leading-tight tracking-[-0.02em]">{f.title}</h3>
                  <p className="mt-3 max-w-[420px] text-[17px] leading-[1.45] text-[var(--fg-soft)]">{f.body}</p>
                  <span className="link-chevron mt-auto pt-6 text-[17px] group-hover:underline">Learn more</span>
                </Link>
              ))}
            </div>
          </div>
        </section>

        {/* Photo & sound */}
        <section className="mx-auto max-w-[980px] px-5 py-20 md:py-28">
          <h2 className="text-center text-[32px] font-semibold tracking-[-0.025em] md:text-[48px]">By photo. By sound.</h2>
          <div className="mt-12 grid gap-12 md:grid-cols-2 md:gap-16">
            <div className="text-center md:text-left">
              <h3 className="text-[24px] font-semibold tracking-[-0.015em]">Identify by photo</h3>
              <p className="mt-3 text-[17px] leading-[1.5] text-[var(--fg-soft)]">
                Take or choose a picture and a model on your phone suggests the species. If it is not confident, it says so
                instead of guessing.
              </p>
              <Link to="/bird-photo-identification" className="link-chevron mt-4 inline-block text-[17px]">How photo identification works</Link>
            </div>
            <div className="text-center md:text-left">
              <h3 className="text-[24px] font-semibold tracking-[-0.015em]">Identify by sound</h3>
              <p className="mt-3 text-[17px] leading-[1.5] text-[var(--fg-soft)]">
                Record a call and BirdNET, from the Cornell Lab of Ornithology, identifies it on your phone, using your
                location to rule out birds that do not live nearby.
              </p>
              <Link to="/bird-sound-identification" className="link-chevron mt-4 inline-block text-[17px]">How sound identification works</Link>
            </div>
          </div>
        </section>

        {/* Waitlist */}
        <section id="waitlist" className="scroll-mt-12 bg-[var(--bg-raised)] py-20 md:py-28">
          <div className="mx-auto max-w-[480px] px-5 text-center">
            <h2 className="text-[32px] font-semibold tracking-[-0.025em] md:text-[48px]">Join the waitlist.</h2>
            <p className="mb-8 mt-4 text-[17px] leading-[1.45] text-[var(--fg-soft)]">
              The beta is rolling out gradually through TestFlight. Leave your iCloud email and we&rsquo;ll send an invite as soon as a spot opens up.
            </p>
            <div className="text-left">
              <WaitlistForm idPrefix="waitlist-hero" />
            </div>
          </div>
        </section>

        {/* FAQ teaser */}
        <section className="mx-auto max-w-[980px] px-5 py-20 md:py-28">
          <h2 className="text-center text-[32px] font-semibold tracking-[-0.025em] md:text-[48px]">Common questions.</h2>
          <div className="mt-12 grid gap-x-16 gap-y-10 md:grid-cols-2">
            {FAQ_TEASER.map(item => (
              <div key={item.q}>
                <h3 className="text-[19px] font-semibold tracking-[-0.01em]">{item.q}</h3>
                <p className="mt-2 text-[17px] leading-[1.5] text-[var(--fg-soft)]">{item.a}</p>
              </div>
            ))}
          </div>
          <p className="mt-12 text-center text-[17px]">
            <Link to="/faq" className="link-chevron">Read all the questions</Link>
          </p>
        </section>
      </main>

      <SiteFooter />
    </div>
  )
}
