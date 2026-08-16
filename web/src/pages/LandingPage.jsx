import React from 'react'
import { Link } from 'react-router-dom'
import DitheredObject from '../components/canvasui/DitheredObject.jsx'
import Glass from '../components/canvasui/Glass.jsx'
import Liquid from '../components/canvasui/Liquid.jsx'
import ParticleReveal from '../components/canvasui/ParticleReveal.jsx'
import Glitch from '../components/canvasui/Glitch.jsx'
import AppStoreBadge from '../components/AppStoreBadge.jsx'
import birdMark from '../assets/bird-mark.svg'

const FEATURES = [
  {
    href: '/ai',
    icon: '✨',
    title: 'On-device AI',
    body: 'A CoreML model on your phone identifies species from your photos in seconds — nothing leaves your device until you choose to share it.',
  },
  {
    href: '/community',
    icon: '👥',
    title: 'Community annotation',
    body: 'Every sighting can be reviewed and confirmed by other birders, building a consensus that keeps improving with every visit.',
  },
  {
    href: '/citizen-science',
    icon: '🌐',
    title: 'Citizen science',
    body: "Your sightings feed a shared, growing dataset — geotagged and timestamped — that researchers and conservationists can rely on.",
  },
  {
    href: '/map',
    icon: '🗺️',
    title: 'Live sighting map',
    body: 'Photo and audio sightings from the whole community, plotted in real time. This is the map — see it in action.',
  },
]

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-[#0f1117] text-[#e8eaf0] font-sans overflow-x-hidden">
      {/* Nav */}
      <header className="sticky top-0 z-50 border-b border-white/8 bg-[#0f1117]/80 backdrop-blur-md">
        <div className="mx-auto flex max-w-6xl items-center gap-6 px-6 py-4">
          <span className="flex items-center gap-2 text-lg font-bold">🐦 BirdMap</span>
          <nav className="ml-auto hidden items-center gap-6 text-sm text-white/70 sm:flex">
            <Link to="/ai" className="hover:text-white transition-colors">AI</Link>
            <Link to="/community" className="hover:text-white transition-colors">Community</Link>
            <Link to="/citizen-science" className="hover:text-white transition-colors">Citizen Science</Link>
          </nav>
          <Link
            to="/map"
            className="ml-2 inline-block rounded-full bg-gradient-to-r from-teal-500 to-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-lg shadow-teal-900/30 transition-transform hover:scale-105 sm:ml-6"
          >
            What We Built →
          </Link>
        </div>
      </header>

      {/* Hero */}
      <section className="relative mx-auto grid max-w-6xl grid-cols-1 items-center gap-10 px-6 pt-16 pb-20 md:grid-cols-2 md:pt-24">
        <div>
          <Glitch
            intensity={0.15}
            wait={4200}
            duration={220}
            className="inline-block"
          >
            <p className="mb-4 text-xs font-semibold uppercase tracking-[0.2em] text-teal-400">
              Citizen science, in your pocket
            </p>
          </Glitch>
          <h1 className="text-4xl font-extrabold leading-[1.05] tracking-tight text-white sm:text-5xl md:text-6xl">
            Every bird you see<br />becomes <span className="bg-gradient-to-r from-teal-400 to-sky-400 bg-clip-text text-transparent">data that matters</span>.
          </h1>
          <p className="mt-6 max-w-md text-lg leading-relaxed text-white/60">
            Snap a photo or record a call. On-device AI suggests the species instantly,
            the community verifies it, and a live map of the whole flock takes shape —
            in real time, built by people like you.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-4">
            <Link
              to="/map"
              className="inline-block rounded-full bg-gradient-to-r from-teal-500 to-sky-600 px-6 py-3 text-sm font-semibold text-white shadow-xl shadow-teal-900/40 transition-transform hover:scale-105"
            >
              What We Built — See the Map
            </Link>
            <AppStoreBadge />
          </div>
        </div>

        <div className="relative mx-auto aspect-square w-full max-w-md">
          <div className="absolute inset-0 rounded-full bg-gradient-to-br from-teal-500/20 via-sky-600/10 to-purple-500/20 blur-3xl" />
          <DitheredObject
            src={birdMark}
            method="bayer"
            gridSize={4}
            highlight="#2dd4bf"
            background=""
            autoRotate
            autoRotateSpeed={2.4}
            className="relative h-full w-full"
          />
        </div>
      </section>

      {/* Mission — glass panel */}
      <section className="mx-auto max-w-4xl px-6 pb-24">
        <Glass
          className="rounded-3xl border border-white/10"
          radius={24}
          blur={0.4}
        >
          <div className="bg-gradient-to-br from-white/[0.06] to-white/[0.02] p-10 sm:p-14 rounded-3xl">
            <h2 className="mb-4 text-sm font-semibold uppercase tracking-[0.2em] text-teal-400">What we are</h2>
            <p className="text-2xl font-medium leading-relaxed text-white/90 sm:text-3xl">
              BirdMap is a citizen-science app that turns everyday bird sightings into a
              living, self-improving dataset — identified on-device, verified by a
              community, and mapped for everyone.
            </p>
            <p className="mt-6 max-w-2xl text-base leading-relaxed text-white/50">
              No sighting sits idle. Photos train better on-device models. Audio feeds
              Cornell's BirdNET. Annotations sharpen the consensus. It's a loop that gets
              smarter every time someone looks up.
            </p>
          </div>
        </Glass>
      </section>

      {/* Feature grid — liquid hover cards */}
      <section className="mx-auto max-w-6xl px-6 pb-24">
        <h2 className="mb-8 text-center text-sm font-semibold uppercase tracking-[0.2em] text-white/40">
          How it fits together
        </h2>
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          {FEATURES.map(f => (
            <Link key={f.href} to={f.href} className="group block">
              <Liquid className="rounded-2xl border border-white/10 transition-colors group-hover:border-teal-400/40" radius={20}>
                <div className="flex h-full flex-col gap-3 bg-white/[0.03] p-7">
                  <span className="text-3xl">{f.icon}</span>
                  <h3 className="text-lg font-semibold text-white">{f.title}</h3>
                  <p className="text-sm leading-relaxed text-white/55">{f.body}</p>
                  <span className="mt-auto pt-2 text-sm font-medium text-teal-400 opacity-0 transition-opacity group-hover:opacity-100">
                    Learn more →
                  </span>
                </div>
              </Liquid>
            </Link>
          ))}
        </div>
      </section>

      {/* Stats — particle reveal */}
      <section className="mx-auto max-w-6xl px-6 pb-24">
        <ParticleReveal className="rounded-3xl" particleSize={1.6} density={0.9}>
          <div className="grid grid-cols-1 gap-8 rounded-3xl border border-white/10 bg-gradient-to-br from-teal-500/10 to-sky-600/10 p-10 text-center sm:grid-cols-3 sm:p-14">
            <div>
              <div className="text-4xl font-extrabold text-white">On-device</div>
              <div className="mt-1 text-sm text-white/50">AI identification, zero server round-trip</div>
            </div>
            <div>
              <div className="text-4xl font-extrabold text-white">Live</div>
              <div className="mt-1 text-sm text-white/50">Community map, updated in real time</div>
            </div>
            <div>
              <div className="text-4xl font-extrabold text-white">Open</div>
              <div className="mt-1 text-sm text-white/50">Built on Cornell's BirdNET &amp; Google's AIY Birds</div>
            </div>
          </div>
        </ParticleReveal>
      </section>

      {/* CTA */}
      <section className="mx-auto max-w-4xl px-6 pb-28 text-center">
        <h2 className="text-3xl font-bold text-white sm:text-4xl">Ready to see what's flying nearby?</h2>
        <p className="mx-auto mt-4 max-w-lg text-white/55">
          Explore the live community map, or grab the app and start contributing sightings today.
        </p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
          <Link
            to="/map"
            className="inline-block rounded-full bg-gradient-to-r from-teal-500 to-sky-600 px-7 py-3.5 text-base font-semibold text-white shadow-xl shadow-teal-900/40 transition-transform hover:scale-105"
          >
            What We Built — Open the Map
          </Link>
          <AppStoreBadge size="lg" />
        </div>
      </section>

      <footer className="border-t border-white/6 px-6 py-8 text-center text-sm text-white/35">
        <Link to="/terms" className="hover:text-white/60 transition-colors">Terms of Service</Link>
        <span className="mx-3">·</span>
        © 2026 BirdMap · Citizen Science
      </footer>
    </div>
  )
}
