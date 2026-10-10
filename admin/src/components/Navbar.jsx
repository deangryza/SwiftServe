// src/components/Navbar.jsx
// Top navigation bar: mobile menu button, breadcrumb, search, dark mode
// toggle (UI only), current date, notifications, and profile dropdown.

import { useState } from 'react'
import { Menu, Moon, Sun, CalendarDays } from 'lucide-react'
import SearchBar from './SearchBar'
import NotificationDropdown from './NotificationDropdown'
import ProfileDropdown from './ProfileDropdown'

const today = new Date()
const formattedDate = today.toLocaleDateString('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  year: 'numeric',
})

export default function Navbar({ onOpenMobileSidebar, breadcrumb = ['Dashboard'] }) {
  const [darkMode, setDarkMode] = useState(false)

  return (
    <header className="sticky top-0 z-20 flex h-14 shrink-0 items-center gap-2 border-b border-surface-200 bg-white/90 px-3 backdrop-blur-md sm:h-16 sm:gap-3 sm:px-5 lg:px-6">
      <button
        onClick={onOpenMobileSidebar}
        className="flex h-9 w-9 items-center justify-center rounded-xl border border-surface-200 text-ink-600 lg:hidden"
      >
        <Menu size={18} />
      </button>

      <div className="hidden text-sm text-ink-600/50 sm:block">
        {breadcrumb.join(' / ')}
      </div>
      <span className="truncate text-sm font-semibold text-ink-900 sm:hidden">SwiftServe Admin</span>

      <div className="ml-auto flex items-center gap-2 sm:gap-3">
        <SearchBar />

        <div className="hidden items-center gap-1.5 rounded-xl border border-surface-200 px-3 py-1.5 text-xs font-medium text-ink-600 md:flex">
          <CalendarDays size={14} />
          {formattedDate}
        </div>

        <button
          onClick={() => setDarkMode((d) => !d)}
          aria-label="Toggle dark mode"
          className="hidden h-9 w-9 items-center justify-center rounded-xl border border-surface-200 text-ink-600 transition-colors hover:bg-surface-100 sm:flex"
        >
          {darkMode ? <Sun size={17} /> : <Moon size={17} />}
        </button>

        <NotificationDropdown />
        <div className="hidden h-6 w-px bg-surface-200 sm:block" />
        <ProfileDropdown />
      </div>
    </header>
  )
}
