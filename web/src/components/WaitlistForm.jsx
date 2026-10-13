import React, { useState } from 'react'
import { Check } from 'lucide-react'
import { submitWaitlistSignup } from '../firebase.js'
import { isIcloudEmail } from '../lib/waitlist.js'

const inputClass = 'field'

/**
 * Name + iCloud email form that writes to the `waitlist` Firestore collection (see firebase.js's
 * submitWaitlistSignup) — no backend, same as the rest of this site. Used inline in the hero and
 * inside WaitlistButton's modal. `autoFocusEmail` is for the modal only; the hero form must not
 * steal focus on page load.
 */
export default function WaitlistForm({ autoFocusEmail = false, idPrefix = 'waitlist' }) {
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  // Honeypot: a field real visitors never see or fill; a bot filling every input trips it.
  const [company, setCompany] = useState('')
  const [status, setStatus] = useState('idle') // idle | submitting | done | error
  const [error, setError] = useState('')

  async function submit(e) {
    e.preventDefault()
    if (company) { setStatus('done'); return }   // honeypot tripped — pretend success, add nothing
    const trimmedEmail = email.trim()
    if (!isIcloudEmail(trimmedEmail)) {
      setError('Please use your iCloud email (ending in @icloud.com, @me.com or @mac.com) — the beta is delivered through TestFlight to your Apple ID.')
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

  if (status === 'done') {
    return (
      <div className="py-2">
        <div className="flex h-11 w-11 items-center justify-center rounded-full border border-[var(--accent)] text-[var(--accent)]">
          <Check size={20} strokeWidth={2} />
        </div>
        <h3 className="mt-4 text-[24px] font-semibold tracking-[-0.02em]">You&rsquo;re on the list</h3>
        <p className="mt-2 max-w-[34ch] text-[14px] leading-relaxed text-[var(--fg-soft)]">
          We&rsquo;re rolling the beta out slowly so we can keep up with everyone&rsquo;s feedback.
          We&rsquo;ll send a TestFlight invite to your iCloud email when it&rsquo;s your turn.
        </p>
      </div>
    )
  }

  return (
    <form onSubmit={submit} className="space-y-3" noValidate>
      <label className="block" htmlFor={`${idPrefix}-name`}>
        <span className="sr-only">Name (optional)</span>
        <input
          id={`${idPrefix}-name`}
          type="text"
          value={name}
          onChange={e => setName(e.target.value)}
          placeholder="Name (optional)"
          autoComplete="name"
          className={inputClass}
        />
      </label>
      <label className="block" htmlFor={`${idPrefix}-email`}>
        <span className="sr-only">iCloud email</span>
        <input
          id={`${idPrefix}-email`}
          type="email"
          required
          autoFocus={autoFocusEmail}
          value={email}
          onChange={e => setEmail(e.target.value)}
          placeholder="you@icloud.com"
          autoComplete="email"
          inputMode="email"
          className={inputClass}
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

      {error && <p role="alert" className="text-[13px] leading-snug text-[var(--accent)]">{error}</p>}

      <button
        type="submit"
        disabled={status === 'submitting'}
        className="btn-blue w-full px-5 py-3 text-[17px]"
      >
        {status === 'submitting' ? 'Joining…' : 'Join the waitlist'}
      </button>

      <p className="text-[12px] leading-relaxed text-[var(--fg-soft)]">
        iCloud email only (@icloud.com, @me.com, @mac.com): the beta is sent through Apple&rsquo;s
        TestFlight. We&rsquo;ll only use it to tell you about BioMap access. No spam.
      </p>
    </form>
  )
}
