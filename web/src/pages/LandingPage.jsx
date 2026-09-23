import React from 'react'
import { Link } from 'react-router-dom'
import AppStoreBadge from '../components/AppStoreBadge.jsx'
import birdMark from '../assets/bird-mark.svg'

const FEATURES = [
  {
    n: '01',
    href: '/ai',
    title: 'On-device AI',
    body: 'A model on your phone identifies species from your photos in seconds — nothing leaves your device until you choose to share it.',
  },
  {
    n: '02',
    href: '/community',
    title: 'Community annotation',
    body: 'Every sighting can be reviewed and confirmed by other birders, building a consensus that keeps improving with every visit.',
  },
  {
    n: '03',
    href: '/citizen-science',
    title: 'Citizen science',
    body: 'Your sightings feed a shared, growing dataset — geotagged and timestamped — that researchers and conservationists can rely on.',
  },
  {
    n: '04',
    href: '/map',
    title: 'Live sighting map',
    body: 'Photo and audio sightings from the whole community, plotted in real time as they come in.',
  },
]

const NAV = [
  { to: '/ai', label: 'AI' },
  { to: '/community', label: 'Community' },
  { to: '/citizen-science', label: 'Citizen Science' },
]

function Rule({ className = '' }) {
  return <div className={`h-px w-full bg-[var(--rule)] ${className}`} />
}

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-[var(--paper)] font-sans text-[var(--ink)] antialiased selection:bg-[var(--clay-soft)] selection:text-[var(--ink)]">
      {/* Nav */}
      <header className="sticky top-0 z-50 bg-[var(--paper)]/90 backdrop-blur-sm">
        <div className="mx-auto flex max-w-5xl items-center gap-8 px-6 py-5">
          <Link to="/" className="flex items-center gap-2.5">
            <img src={birdMark} alt="" className="h-5 w-5" />
            <span className="font-serif text-[17px] italic tracking-tight">BirdMap</span>
          </Link>
          <nav className="ml-auto hidden items-center gap-7 text-[13px] uppercase tracking-[0.08em] text-[var(--ink-soft)] sm:flex">
            {NAV.map(item => (
              <Link key={item.to} to={item.to} className="transition-colors hover:text-[var(--ink)]">
                {item.label}
              </Link>
            ))}
          </nav>
          <Link
            to="/map"
            className="ml-2 shrink-0 border border-[var(--ink)] px-4 py-2 text-[13px] font-medium tracking-tight text-[var(--ink)] transition-colors hover:bg-[var(--ink)] hover:text-[var(--paper)] sm:ml-0"
          >
            Open the map
          </Link>
        </div>
        <Rule />
      </header>

      {/* Hero */}
      <section className="mx-auto max-w-5xl px-6 pb-16 pt-16 md:pb-24 md:pt-20">
        <p className="text-[13px] uppercase tracking-[0.14em] text-[var(--clay)]">
          Citizen science, one sighting at a time
        </p>
        <h1 className="mt-5 max-w-3xl font-serif text-[42px] font-medium leading-[1.08] tracking-[-0.01em] sm:text-[56px] md:text-[68px]">
          Every bird you see becomes <em className="italic text-[var(--clay)]">data that matters</em>.
        </h1>
        <p className="mt-7 max-w-lg text-[17px] leading-relaxed text-[var(--ink-soft)]">
          Snap a photo or record a call. On-device AI suggests the species instantly,
          the community verifies it, and a live map of the whole flock takes shape —
          built by people like you.
        </p>
        <div className="mt-9 flex flex-wrap items-center gap-5">
          <Link
            to="/map"
            className="group inline-flex items-center gap-2 bg-[var(--ink)] px-6 py-3 text-[14px] font-medium text-[var(--paper)] transition-colors hover:bg-[var(--clay)]"
          >
            Open the live map
            <span className="transition-transform group-hover:translate-x-0.5">→</span>
          </Link>
          <AppStoreBadge />
        </div>
      </section>

      <div className="mx-auto max-w-5xl px-6"><Rule /></div>

      {/* Mission */}
      <section className="mx-auto grid max-w-5xl grid-cols-1 gap-10 px-6 py-20 md:grid-cols-[0.9fr_1.1fr] md:gap-16">
        <p className="font-serif text-[26px] font-normal italic leading-[1.35] text-[var(--ink)] sm:text-[30px]">
          BirdMap turns everyday bird sightings into a living, self-improving dataset — identified
          on-device, verified by a community, and mapped for everyone.
        </p>
        <p className="max-w-[60ch] self-end text-[15px] leading-relaxed text-[var(--ink-soft)]">
          Photos are classified locally by a model built on Google's AIY Birds. Audio recordings
          are matched against Cornell's BirdNET. Every result can be confirmed or corrected by
          other birders, sharpening the consensus each time someone looks up.
        </p>
      </section>

      <div className="mx-auto max-w-5xl px-6"><Rule /></div>

      {/* Features */}
      <section className="mx-auto max-w-5xl px-6 py-20">
        <h2 className="font-serif text-[26px] italic">How it fits together</h2>
        <div className="mt-10">
          {FEATURES.map(f => (
            <Link
              key={f.href}
              to={f.href}
              className="group grid grid-cols-[3rem_1fr_auto] items-start gap-5 border-t border-[var(--rule)] py-8 last:border-b sm:grid-cols-[3.5rem_1fr_auto] sm:gap-8"
            >
              <span className="font-serif text-[22px] italic text-[var(--ink-soft)]/60 transition-colors group-hover:text-[var(--clay)]">
                {f.n}
              </span>
              <span>
                <h3 className="text-[17px] font-medium tracking-tight">{f.title}</h3>
                <p className="mt-1.5 max-w-lg text-[14.5px] leading-relaxed text-[var(--ink-soft)]">
                  {f.body}
                </p>
              </span>
              <span className="mt-1.5 text-[var(--ink-soft)]/50 transition-all group-hover:translate-x-1 group-hover:text-[var(--clay)]">
                →
              </span>
            </Link>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="border-t border-[var(--rule)] bg-[var(--paper-dim)] bg-grain">
        <div className="mx-auto max-w-5xl px-6 py-24 text-center">
          <h2 className="font-serif text-[32px] italic sm:text-[40px]">
            Ready to see what's flying nearby?
          </h2>
          <p className="mx-auto mt-4 max-w-md text-[15px] leading-relaxed text-[var(--ink-soft)]">
            Explore the live community map, or grab the app and start contributing sightings today.
          </p>
          <div className="mt-9 flex flex-wrap items-center justify-center gap-5">
            <Link
              to="/map"
              className="group inline-flex items-center gap-2 bg-[var(--ink)] px-7 py-3.5 text-[15px] font-medium text-[var(--paper)] transition-colors hover:bg-[var(--clay)]"
            >
              Open the map
              <span className="transition-transform group-hover:translate-x-0.5">→</span>
            </Link>
            <AppStoreBadge size="lg" />
          </div>
        </div>
      </section>

      <footer className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-6 py-8 text-[13px] text-[var(--ink-soft)]">
        <span>© 2026 BirdMap · Citizen Science</span>
        <Link to="/terms" className="underline decoration-[var(--rule)] underline-offset-4 transition-colors hover:text-[var(--ink)] hover:decoration-[var(--ink)]">
          Terms of Service
        </Link>
      </footer>
    </div>
  )
}
