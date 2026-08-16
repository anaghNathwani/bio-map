import React from 'react'

export default function AppStoreBadge({ size = 'md', className = '' }) {
  const dims = size === 'lg' ? { w: 200, h: 60 } : { w: 168, h: 50 }

  return (
    <div
      aria-label="Coming soon to the App Store"
      className={`inline-flex items-center gap-2.5 rounded-xl border border-white/15 bg-black px-4 py-2.5 text-white shadow-lg shadow-black/40 opacity-80 cursor-default ${className}`}
      style={{ width: dims.w, height: dims.h }}
    >
      <svg viewBox="0 0 24 24" width={size === 'lg' ? 26 : 22} height={size === 'lg' ? 26 : 22} fill="currentColor" aria-hidden="true">
        <path d="M16.365 1.43c0 1.14-.468 2.222-1.244 3.014-.849.85-2.15 1.53-3.284 1.44-.14-1.1.42-2.26 1.19-3.02.85-.85 2.27-1.49 3.338-1.434zM20.6 17.14c-.36.83-.79 1.62-1.29 2.36-.68 1.01-1.24 1.71-1.68 2.09-.68.65-1.41 1-2.19 1.02-.56.02-1.24-.16-2.02-.53-.79-.37-1.51-.55-2.19-.55-.71 0-1.46.18-2.26.55-.8.37-1.44.56-1.94.58-.75.03-1.5-.33-2.24-1.05-.48-.42-1.08-1.15-1.79-2.19-.76-1.1-1.39-2.39-1.89-3.86-.53-1.58-.8-3.11-.8-4.59 0-1.7.37-3.16 1.1-4.4.57-.98 1.34-1.76 2.3-2.34.95-.57 1.98-.87 3.09-.89.6-.01 1.4.19 2.4.6.99.4 1.63.6 1.9.6.2 0 .91-.24 2.1-.71 1.13-.44 2.08-.62 2.87-.55 2.1.17 3.69 1 4.75 2.5-1.88 1.14-2.81 2.73-2.79 4.77.02 1.59.6 2.92 1.72 3.98.51.49 1.09.87 1.72 1.14-.14.4-.29.79-.45 1.17z"/>
      </svg>
      <span className="leading-tight text-left">
        <span className="block text-[9px] tracking-wide opacity-90">Coming soon to the</span>
        <span className="block font-semibold text-[15px] -mt-0.5">App Store</span>
      </span>
    </div>
  )
}
