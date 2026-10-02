import React, { useEffect, useRef, useState } from 'react'
import { X, Check } from 'lucide-react'
import { submitWaitlistSignup } from '../firebase.js'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

/**
 * "Join the Waitlist" — a button that opens a small modal collecting name + email, and writes it
 * straight to Firestore (see firebase.js's submitWaitlistSignup) — no backend, same as the rest
 * of this site. ml_pipeline/notify_waitlist_signups.py polls that collection on a schedule and
 * emails new signups; nothing here ever reads it back.
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
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  // Honeypot: a field real visitors never see or fill; a bot filling every input trips it.
  const [company, setCompany] = useState('')
  const [status, setStatus] = useState('idle') // idle | submitting | done | error
  const [error, setError] = useState('')
  const dialogRef = useRef(null)
  const emailRef = useRef(null)

  useEffect(() => {
    emailRef.current?.focus()
    function onKey(e) { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [onClose])

  async function submit(e) {
    e.preventDefault()
    if (company) { setStatus('done'); return }   // honeypot tripped — pretend success, add nothing
    const trimmedEmail = email.trim()
    if (!EMAIL_RE.test(trimmedEmail)) {
      setError('That email address doesn’t look right.')
      return
    }
    setStatus('submitting')
    setError('')
    try {
      await submitWaitlistSignup({ email: trimmedEmail, name: name.trim() })
      setStatus('done')
    } catch {
      setStatus('error')
      setError('Couldn’t reach the waitlist right now. Please try again in a moment.')
    }
  }

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-[var(--ink)]/40 px-6 backdrop-blur-sm"
      onMouseDown={e => { if (e.target === e.currentTarget) onClose() }}
    >
      <div
        ref={dialogRef}
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

        {status === 'done' ? (
          <div className="py-4 text-center">
            <div className="mx-auto flex h-11 w-11 items-center justify-center rounded-full border border-[var(--clay)] text-[var(--clay)]">
              <Check size={20} strokeWidth={2} />
            </div>
            <h2 className="mt-4 font-serif text-[22px] italic">You&rsquo;re on the list</h2>
            <p className="mx-auto mt-2 max-w-[28ch] text-[14px] leading-relaxed text-[var(--ink-soft)]">
              We&rsquo;re rolling the beta out slowly so we can keep up with everyone&rsquo;s feedback.
              We&rsquo;ll email you when it&rsquo;s your turn.
            </p>
          </div>
        ) : (
          <>
            <p className="text-[13px] uppercase tracking-[0.14em] text-[var(--clay)]">Beta access</p>
            <h2 id="waitlist-title" className="mt-2 font-serif text-[24px] italic leading-tight">
              Join the waitlist
            </h2>
            <p className="mt-2 text-[14px] leading-relaxed text-[var(--ink-soft)]">
              The app is rolling out gradually. Leave your email and we&rsquo;ll let you know as soon
              as a spot opens up.
            </p>

            <form onSubmit={submit} className="mt-6 space-y-3">
              <label className="block">
                <span className="sr-only">Name (optional)</span>
                <input
                  type="text"
                  value={name}
                  onChange={e => setName(e.target.value)}
                  placeholder="Name (optional)"
                  autoComplete="name"
                  className="w-full border border-[var(--rule)] bg-transparent px-3.5 py-2.5 text-[14.5px] text-[var(--ink)] outline-none placeholder:text-[var(--ink-soft)]/70 focus:border-[var(--ink)]"
                />
              </label>
              <label className="block">
                <span className="sr-only">Email</span>
                <input
                  ref={emailRef}
                  type="email"
                  required
                  value={email}
                  onChange={e => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  autoComplete="email"
                  className="w-full border border-[var(--rule)] bg-transparent px-3.5 py-2.5 text-[14.5px] text-[var(--ink)] outline-none placeholder:text-[var(--ink-soft)]/70 focus:border-[var(--ink)]"
                />
              </label>
              {/* Honeypot — hidden from sighted users and screen readers; bots that fill every field trip it. */}
              <input
                type="text"
                value={company}
                onChange={e => setCompany(e.target.value)}
                tabIndex={-1}
                autoComplete="off"
                aria-hidden="true"
                className="absolute left-[-9999px] h-0 w-0 opacity-0"
              />

              {error && <p className="text-[13px] leading-snug text-[var(--clay)]">{error}</p>}

              <button
                type="submit"
                disabled={status === 'submitting'}
                className="mt-1 inline-flex w-full items-center justify-center gap-2 bg-[var(--ink)] px-5 py-3 text-[14px] font-medium text-[var(--paper)] transition-colors hover:bg-[var(--clay)] disabled:opacity-60"
              >
                {status === 'submitting' ? 'Joining…' : 'Join the waitlist'}
              </button>
            </form>

            <p className="mt-4 text-[12px] leading-relaxed text-[var(--ink-soft)]/80">
              We&rsquo;ll only use this to tell you about BirdMap access. No spam.
            </p>
          </>
        )}
      </div>
    </div>
  )
}
