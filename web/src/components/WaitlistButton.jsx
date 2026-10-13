import React, { useEffect, useState } from 'react'
import { X } from 'lucide-react'
import WaitlistForm from './WaitlistForm.jsx'

/**
 * "Join the Waitlist" — a button that opens a small modal around WaitlistForm, which writes
 * straight to Firestore (see firebase.js's submitWaitlistSignup) — no backend, same as the rest of
 * this site. ml_pipeline/notify_waitlist_signups.py polls that collection on a schedule and emails
 * new signups; nothing here ever reads it back.
 */
export default function WaitlistButton({ size = 'md', className = '' }) {
  const [open, setOpen] = useState(false)
  const large = size === 'lg'

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={
          large
            ? `group inline-flex items-center gap-2 border border-[var(--ink)] px-7 py-3.5 text-[15px] font-medium text-[var(--ink)] transition-colors hover:bg-[var(--ink)] hover:text-[var(--paper)] ${className}`
            : `group inline-flex items-center gap-2 border border-[var(--ink)] px-6 py-3 text-[14px] font-medium text-[var(--ink)] transition-colors hover:bg-[var(--ink)] hover:text-[var(--paper)] ${className}`
        }
      >
        Join the waitlist
        <span className="transition-transform group-hover:translate-x-0.5">→</span>
      </button>
      {open && <WaitlistModal onClose={() => setOpen(false)} />}
    </>
  )
}

function WaitlistModal({ onClose }) {
  useEffect(() => {
    function onKey(e) { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [onClose])

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-[var(--ink)]/40 px-6 backdrop-blur-sm"
      onMouseDown={e => { if (e.target === e.currentTarget) onClose() }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="waitlist-title"
        className="relative w-full max-w-sm border border-[var(--rule)] bg-[var(--paper)] p-7 shadow-xl"
      >
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="absolute right-4 top-4 text-[var(--ink-soft)] transition-colors hover:text-[var(--ink)]"
        >
          <X size={18} strokeWidth={1.75} />
        </button>
        <p className="text-[13px] uppercase tracking-[0.14em] text-[var(--clay)]">Beta access</p>
        <h2 id="waitlist-title" className="mt-2 font-serif text-[24px] italic leading-tight">
          Join the waitlist
        </h2>
        <p className="mb-6 mt-2 text-[14px] leading-relaxed text-[var(--ink-soft)]">
          The app is rolling out gradually. Leave your iCloud email and we&rsquo;ll send a TestFlight
          invite as soon as a spot opens up.
        </p>
        <WaitlistForm autoFocusEmail idPrefix="waitlist-modal" />
      </div>
    </div>
  )
}
