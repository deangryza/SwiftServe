// src/components/NotificationDropdown.jsx
// Bell icon + dropdown panel with static notification items.

import { useState, useRef, useEffect } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { Bell, ShieldAlert, CalendarClock, FileWarning } from 'lucide-react'

const notifications = [
  { id: 1, icon: ShieldAlert, color: 'text-warning-600 bg-warning-50', text: 'Miguel Torres submitted worker verification', time: '12m ago' },
  { id: 2, icon: CalendarClock, color: 'text-swift-600 bg-swift-50', text: 'New booking BKG-5041 awaiting confirmation', time: '38m ago' },
  { id: 3, icon: FileWarning, color: 'text-danger-600 bg-danger-50', text: 'New complaint filed against RPT-7018', time: '1h ago' },
  { id: 4, icon: ShieldAlert, color: 'text-success-600 bg-success-50', text: 'Ana Bautista passed face verification', time: '2h ago' },
]

export default function NotificationDropdown() {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

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
        className="relative flex h-9 w-9 items-center justify-center rounded-xl border border-surface-200 text-ink-600 transition-colors hover:bg-surface-100"
      >
        <Bell size={17} />
        <span className="absolute -right-0.5 -top-0.5 flex h-2.5 w-2.5">
          <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-danger-400 opacity-75" />
          <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-danger-500" />
        </span>
      </button>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -8, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8, scale: 0.97 }}
            transition={{ duration: 0.15 }}
            className="absolute right-0 z-30 mt-2 w-80 overflow-hidden rounded-2xl border border-surface-200 bg-white shadow-card-hover"
          >
            <div className="border-b border-surface-200 px-4 py-3">
              <p className="font-display text-sm font-semibold text-ink-900">Notifications</p>
            </div>
            <div className="max-h-80 overflow-y-auto">
              {notifications.map((n) => {
                const Icon = n.icon
                return (
                  <div key={n.id} className="flex gap-3 border-b border-surface-100 px-4 py-3 last:border-0 hover:bg-surface-50">
                    <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${n.color}`}>
                      <Icon size={14} />
                    </span>
                    <div className="min-w-0">
                      <p className="text-xs leading-snug text-ink-800">{n.text}</p>
                      <p className="mt-0.5 text-[11px] text-ink-600/50">{n.time}</p>
                    </div>
                  </div>
                )
              })}
            </div>
            <button className="w-full px-4 py-2.5 text-center text-xs font-medium text-swift-600 hover:bg-surface-50">
              View all notifications
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
