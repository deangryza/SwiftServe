// src/components/ProfileDropdown.jsx
// Admin avatar + dropdown with profile, settings, and logout actions (static).

import { useState, useRef, useEffect } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ChevronDown, User, Settings, LogOut } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { signOut } from 'firebase/auth'
import { auth } from '../lib/firebase'

export default function ProfileDropdown() {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  const navigate = useNavigate()

  useEffect(() => {
    function handleClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label="Open administrator menu"
        aria-expanded={open}
        className="flex items-center gap-2 rounded-xl border border-surface-200 py-1 pl-1 pr-2 transition-colors hover:bg-surface-100"
      >
        <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-swift-500 font-display text-xs font-semibold text-white">
          {(auth.currentUser?.displayName || auth.currentUser?.email || 'A').slice(0, 2).toUpperCase()}
        </span>
        <ChevronDown size={14} className="hidden text-ink-600/60 sm:block" />
      </button>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8, scale: 0.97 }}
            transition={{ duration: 0.15 }}
            className="fixed left-3 right-3 top-14 z-30 mt-2 overflow-hidden rounded-2xl border border-surface-200 bg-white shadow-card-hover sm:absolute sm:left-auto sm:right-0 sm:top-auto sm:w-56"
          >
            <div className="border-b border-surface-200 px-4 py-3">
              <p className="text-sm font-semibold text-ink-900">{auth.currentUser?.displayName || auth.currentUser?.email}</p>
              <p className="text-xs text-ink-600/50">Administrator</p>
            </div>
            <ul className="py-1.5 text-sm">
              <li>
                <button onClick={() => { setOpen(false); navigate('/dashboard/profile'); }} className="flex w-full items-center gap-2.5 px-4 py-2 text-ink-700 hover:bg-surface-50">
                  <User size={15} /> Profile
                </button>
              </li>
              <li>
                <button className="flex w-full items-center gap-2.5 px-4 py-2 text-ink-700 hover:bg-surface-50">
                  <Settings size={15} /> Settings
                </button>
              </li>
              <li>
                <button
                  onClick={async () => {
                    await signOut(auth)
                    navigate('/', { replace: true })
                  }}
                  className="flex w-full items-center gap-2.5 px-4 py-2 text-danger-600 hover:bg-danger-50"
                >
                  <LogOut size={15} /> Logout
                </button>
              </li>
            </ul>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
