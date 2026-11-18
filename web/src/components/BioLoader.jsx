import React, { useEffect, useRef, useState } from 'react'
import { ORGANISMS, SAMPLES } from '../lib/organisms.js'

// A brief pause per shape: most loads last a second or two, and a long pause on the first shape (the bird) meant
// short loads never got past it. Keep in step with BioLoaderTimeline.swift in the iOS app.
const HOLD_MS = 450
const MORPH_MS = 800
const FADE_PAUSE_MS = 900   // Reduce Motion: how long each shape stays before dissolving to the next
const FADE_MS = 300
const NUCLEUS_FROM = 5 // organisms at or after this index are microbes (Amoeba onward) and get a nucleus

const ease = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)

/** Closed Catmull-Rom spline through the sampled contour, as a cubic-bezier SVG path. */
function contourPath(radii, size) {
  const c = size / 2
  const R = size * 0.42
  const pts = radii.map((r, i) => {
    const a = (2 * Math.PI * i) / SAMPLES
    return [c + r * R * Math.cos(a), c - r * R * Math.sin(a)]
  })
  const n = pts.length
  let d = `M${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
    d += `C${c1[0].toFixed(2)} ${c1[1].toFixed(2)} ${c2[0].toFixed(2)} ${c2[1].toFixed(2)} ${p2[0].toFixed(2)} ${p2[1].toFixed(2)}`
  }
  return d + 'Z'
}

/**
 * BioMap's loading animation: the brand bird melts into a butterfly, a fish, a leaf, a jellyfish and
 * on down to single-celled life (amoeba, bacterium, yeast, paramecium, diatom), then back to the
 * bird, drawn as one flat line (with Reduce Motion on, the shapes dissolve into each other instead of moving). Every shape is a radius-vs-angle table (web/scripts/gen_organisms.py, shared with the iOS
 * app), so morphing is just interpolating radii. Honors prefers-reduced-motion by dissolving between shapes instead of moving.
 */
export default function BioLoader({ size = 160, label = true, className = '' }) {
  const pathRef = useRef(null)
  const nucleusRef = useRef(null)
  const [index, setIndex] = useState(0)

  useEffect(() => {
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      // Reduce Motion: don't morph or move, but still play the whole carousel by dissolving from shape to shape
      // (it used to sit on one still bird, which reads as a broken loader).
      let i = 0
      let timer
      const next = () => {
        pathRef.current?.style.setProperty('opacity', '0')
        timer = setTimeout(() => {
          i = (i + 1) % ORGANISMS.length
          pathRef.current?.setAttribute('d', contourPath(ORGANISMS[i].r, size))
          nucleusRef.current?.setAttribute('opacity', i >= NUCLEUS_FROM ? '1' : '0')
          pathRef.current?.style.setProperty('opacity', '1')
          setIndex(i)
          timer = setTimeout(next, FADE_PAUSE_MS)
        }, FADE_MS)
      }
      timer = setTimeout(next, FADE_PAUSE_MS)
      return () => clearTimeout(timer)
    }
    const count = ORGANISMS.length
    let raf
    let start
    let shown = 0
    const tick = now => {
      if (start === undefined) start = now
      const cycle = HOLD_MS + MORPH_MS
      const elapsed = now - start
      const step = Math.floor(elapsed / cycle)
      const within = elapsed - step * cycle
      const from = ORGANISMS[step % count]
      const toIdx = (step + 1) % count
      const to = ORGANISMS[toIdx]
      const t = within < HOLD_MS ? 0 : ease((within - HOLD_MS) / MORPH_MS)
      const radii = from.r.map((r, i) => r + (to.r[i] - r) * t)
      const d = contourPath(radii, size)
      pathRef.current?.setAttribute('d', d)
      // Nucleus fades in while heading into microbes, out when coming back to the bird.
      const a = step % count >= NUCLEUS_FROM ? 1 : 0
      const b = toIdx >= NUCLEUS_FROM ? 1 : 0
      nucleusRef.current?.setAttribute('opacity', String(a + (b - a) * t))
      const current = t > 0.5 ? toIdx : step % count
      if (current !== shown) { shown = current; setIndex(current) }
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [size])

  const initial = contourPath(ORGANISMS[0].r, size)
  const c = size / 2

  return (
    <div role="status" aria-live="polite" className={`inline-flex flex-col items-center ${className}`}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true" className="overflow-visible">
        <path ref={pathRef} d={initial} fill="none" stroke="var(--accent)" strokeWidth={Math.max(2, size * 0.016)} strokeLinejoin="round" style={{ transition: `opacity ${FADE_MS}ms ease` }} />
        <circle ref={nucleusRef} cx={c} cy={c} r={size * 0.05} fill="var(--accent)" opacity="0" className="bio-loader-pulse" style={{ transformOrigin: 'center' }} />
      </svg>
      {label && (
        <span className="mt-4 h-5 text-[15px] font-semibold text-[var(--fg-soft)]">
          {ORGANISMS[index].name}
        </span>
      )}
      <span className="sr-only">Loading</span>
    </div>
  )
}
