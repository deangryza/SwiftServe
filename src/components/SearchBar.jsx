// src/components/SearchBar.jsx
// Static search input used in the top navbar. UI only — no backend wiring.

import { Search } from 'lucide-react'
import { useState } from 'react'

export default function SearchBar({ placeholder = 'Search users, bookings, workers...' }) {
  const [value, setValue] = useState('')

  return (
    <div className="relative hidden w-full max-w-sm md:block">
      <Search size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-ink-600/40" />
      <input
        type="text"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-xl border border-surface-200 bg-surface-50 py-2 pl-9 pr-3 text-sm text-ink-900 placeholder:text-ink-600/40 transition-colors focus:border-swift-400 focus:bg-white focus:outline-none"
      />
      <kbd className="pointer-events-none absolute right-2.5 top-1/2 hidden -translate-y-1/2 rounded-md border border-surface-200 bg-white px-1.5 py-0.5 font-mono text-[10px] text-ink-600/40 lg:block">
        ⌘K
      </kbd>
    </div>
  )
}
