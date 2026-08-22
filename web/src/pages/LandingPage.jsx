import React from 'react'
import { Link } from 'react-router-dom'
import { Cpu, Users, Globe, Map as MapIcon, ArrowRight } from 'lucide-react'
import DitheredObject from '../components/canvasui/DitheredObject.jsx'
import AppStoreBadge from '../components/AppStoreBadge.jsx'
import birdMark from '../assets/bird-mark.svg'

const FEATURES = [
  {
    href: '/ai',
    Icon: Cpu,
    title: 'On-device AI',
    body: 'A CoreML model on your phone identifies species from your photos in seconds — nothing leaves your device until you choose to share it.',
  },
  {
    href: '/community',
    Icon: Users,
    title: 'Community annotation',
    body: 'Every sighting can be reviewed and confirmed by other birders, building a consensus that keeps improving with every visit.',
  },
  {
    href: '/citizen-science',
    Icon: Globe,
    title: 'Citizen science',
    body: 'Your sightings feed a shared, growing dataset — geotagged and timestamped — that researchers and conservationists can rely on.',
  },
  {
    href: '/map',
    Icon: MapIcon,
    title: 'Live sighting map',
    body: 'Photo and audio sightings from the whole community, plotted in real time as they come in.',
  },
]

function NavButton({ to, children, className = '' }) {
  return (
    <Link
      to={to}
      className={`inline-flex items-center gap-1.5 rounded-full bg-teal-500 px-4 py-2 text-sm font-semibold text-[#0f1117] transition-[filter] hover:brightness-110 active:brightness-95 ${className}`}
    >
      {children}
    </Link>
  )
}

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-[#0f1117] font-sans text-[#e8eaf0]">
      {/* Nav */}
      <header className="sticky top-0 z-50 border-b border-white/10 bg-[#0f1117]/85 backdrop-blur-md">
        <div className="mx-auto flex max-w-6xl items-center gap-6 px-6 py-4">
          <Link to="/" className="flex items-center gap-2">
            <img src={birdMark} alt="" className="h-6 w-6" />
            <span className="text-[15px] font-semibold tracking-tight">BirdMap</span>
          </Link>
          <nav className="ml-auto hidden items-center gap-6 text-sm text-white/65 sm:flex">
            <Link to="/ai" className="transition-colors hover:text-white">AI</Link>
            <Link to="/community" className="transition-colors hover:text-white">Community</Link>
            <Link to="/citizen-science" className="transition-colors hover:text-white">Citizen Science</Link>
          </nav>
          <NavButton to="/map" className="ml-2 sm:ml-0">Open the map</NavButton>
        </div>
      </header>

      {/* Hero */}
      <section className="mx-auto grid max-w-6xl grid-cols-1 items-center gap-10 px-6 pb-20 pt-16 md:grid-cols-2 md:pt-24">
        <div>
          <h1 className="text-4xl font-semibold leading-[1.1] tracking-tight text-white sm:text-5xl md:text-6xl">
            Every bird you see becomes <span className="text-teal-300">data that matters</span>.
          </h1>
          <p className="mt-6 max-w-md text-lg leading-relaxed text-white/70">
            Snap a photo or record a call. On-device AI suggests the species instantly,
            the community verifies it, and a live map of the whole flock takes shape —
            built by people like you.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-4">
            <Link
              to="/map"
              className="inline-flex items-center gap-2 rounded-full bg-teal-500 px-6 py-3 text-sm font-semibold text-[#0f1117] transition-[filter] hover:brightness-110 active:brightness-95"
            >
              Open the live map
              <ArrowRight className="h-4 w-4" strokeWidth={2} />
            </Link>
            <AppStoreBadge />
          </div>
        </div>

        <DitheredObject
          src={birdMark}
          method="bayer"
          gridSize={4}
          highlight="#2dd4bf"
          background=""
          autoRotate
          autoRotateSpeed={2.4}
          className="relative mx-auto aspect-square w-full max-w-md"
        />
      </section>

      {/* Mission */}
      <section className="mx-auto max-w-3xl border-y border-white/10 px-6 py-20">
        <p className="text-2xl font-medium leading-relaxed text-white sm:text-3xl">
          BirdMap turns everyday bird sightings into a living, self-improving dataset —
          identified on-device, verified by a community, and mapped for everyone.
        </p>
        <p className="mt-6 max-w-[62ch] text-base leading-relaxed text-white/70">
          Photos are classified locally by a CoreML model built on Google's AIY Birds.
          Audio recordings are matched against Cornell's BirdNET. Every result can be
          confirmed or corrected by other birders, sharpening the consensus each time
          someone looks up.
        </p>
      </section>

      {/* Features */}
      <section className="mx-auto max-w-3xl px-6 py-20">
        <h2 className="mb-2 text-2xl font-semibold text-white">How it fits together</h2>
        <div className="mt-8 divide-y divide-white/10 border-t border-white/10">
          {FEATURES.map(f => (
            <Link key={f.href} to={f.href} className="group flex items-start gap-5 py-7">
              <span className="flex h-10 w-10 flex-none items-center justify-center rounded-full border border-white/15 text-teal-300 transition-colors group-hover:border-teal-400/50 group-hover:text-teal-200">
                <f.Icon className="h-[18px] w-[18px]" strokeWidth={1.75} />
              </span>
              <span className="flex-1">
                <h3 className="font-medium text-white">{f.title}</h3>
                <p className="mt-1 max-w-lg text-sm leading-relaxed text-white/70">{f.body}</p>
              </span>
              <ArrowRight className="mt-2.5 h-4 w-4 flex-none text-white/30 transition-colors group-hover:text-teal-300" strokeWidth={1.75} />
            </Link>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="mx-auto max-w-3xl border-t border-white/10 px-6 py-20 text-center">
        <h2 className="text-3xl font-semibold text-white sm:text-4xl">Ready to see what's flying nearby?</h2>
        <p className="mx-auto mt-4 max-w-lg text-white/70">
          Explore the live community map, or grab the app and start contributing sightings today.
        </p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
          <Link
            to="/map"
            className="inline-flex items-center gap-2 rounded-full bg-teal-500 px-7 py-3.5 text-base font-semibold text-[#0f1117] transition-[filter] hover:brightness-110 active:brightness-95"
          >
            Open the map
            <ArrowRight className="h-4 w-4" strokeWidth={2} />
          </Link>
          <AppStoreBadge size="lg" />
        </div>
      </section>

      <footer className="border-t border-white/10 px-6 py-8 text-center text-sm text-white/55">
        <Link to="/terms" className="transition-colors hover:text-white/80">Terms of Service</Link>
        <span className="mx-3">·</span>
        © 2026 BirdMap · Citizen Science
      </footer>
    </div>
  )
}
