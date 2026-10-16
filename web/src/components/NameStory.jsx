import React, { useEffect, useRef, useState } from 'react'
import { X } from 'lucide-react'
import { NAME_STORY, NAME_STORY_TITLE } from '../content/nameStory.js'

/**
 * "Why we changed our name" — a text link that opens the essay in a popup. Esc, the close button or a
 * click on the backdrop close it; focus moves into the dialog on open and back to the link on close.
 */
export default function NameStoryLink({ className = '' }) {
  const [open, setOpen] = useState(false)
  const triggerRef = useRef(null)

  function close() {
    setOpen(false)
    triggerRef.current?.focus()
  }

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        className={`link-chevron ${className}`}
      >
        Why we changed our name
      </button>
      {open && <NameStoryDialog onClose={close} />}
    </>
  )
}

function NameStoryDialog({ onClose }) {
  const closeRef = useRef(null)

  useEffect(() => {
    closeRef.current?.focus()
    const onKey = e => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [onClose])

  return (
    <div
      className="fixed inset-0 z-[100] flex items-end justify-center bg-black/40 backdrop-blur-sm sm:items-center sm:px-6"
      onMouseDown={e => { if (e.target === e.currentTarget) onClose() }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="name-story-title"
        className="relative flex max-h-[92vh] w-full max-w-[640px] flex-col rounded-t-[28px] bg-[var(--bg)] shadow-2xl sm:rounded-[28px]"
      >
        <button
          ref={closeRef}
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="absolute right-4 top-4 flex h-9 w-9 items-center justify-center rounded-full bg-[var(--bg-raised)] text-[var(--fg-soft)] transition-colors hover:text-[var(--fg)]"
        >
          <X size={18} strokeWidth={2} />
        </button>
        <div className="overflow-y-auto px-7 pb-10 pt-12 text-left sm:px-10">
          <p className="text-[13px] font-semibold text-[var(--fg-soft)]">From the BioMap team</p>
          <h2 id="name-story-title" className="mt-2 text-[34px] font-semibold leading-[1.08] tracking-[-0.03em] sm:text-[44px]">
            {NAME_STORY_TITLE}
          </h2>
          <div className="mt-6 space-y-5 text-[17px] leading-[1.6] tracking-[-0.01em] text-[var(--fg)]/90">
            {NAME_STORY.map((p, i) => <p key={i}>{p}</p>)}
          </div>
        </div>
      </div>
    </div>
  )
}
