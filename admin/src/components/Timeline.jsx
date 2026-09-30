// src/components/Timeline.jsx
// Vertical activity timeline shown in the Recent Activity section.
// Each event type maps to an icon + color so the feed reads at a glance.

import { motion } from 'framer-motion'
import { UserPlus, ShieldCheck, CalendarPlus, CheckCircle2, FileWarning, Ban } from 'lucide-react'

const EVENT_STYLES = {
  worker_registered: { icon: UserPlus, color: 'text-swift-600', bg: 'bg-swift-50' },
  worker_verified: { icon: ShieldCheck, color: 'text-success-600', bg: 'bg-success-50' },
  booking_created: { icon: CalendarPlus, color: 'text-violet-500', bg: 'bg-violet-50' },
  booking_completed: { icon: CheckCircle2, color: 'text-success-600', bg: 'bg-success-50' },
  complaint_submitted: { icon: FileWarning, color: 'text-warning-600', bg: 'bg-warning-50' },
  account_suspended: { icon: Ban, color: 'text-danger-600', bg: 'bg-danger-50' },
}

export default function Timeline({ events }) {
  return (
    <ol className="relative space-y-5 before:absolute before:left-[15px] before:top-2 before:h-[calc(100%-16px)] before:w-px before:bg-surface-200">
      {events.map((event, index) => {
        const style = EVENT_STYLES[event.type] || EVENT_STYLES.booking_created
        const Icon = style.icon
        return (
          <motion.li
            key={event.id}
            initial={{ opacity: 0, x: -8 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.3, delay: index * 0.03 }}
            className="relative flex items-start gap-3 pl-0"
          >
            <span className={`relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full ${style.bg} ${style.color}`}>
              <Icon size={15} />
            </span>
            <div className="min-w-0 pt-1">
              <p className="text-sm text-ink-800 leading-snug">{event.text}</p>
              <p className="mt-0.5 font-mono text-[11px] text-ink-600/50">{event.time}</p>
            </div>
          </motion.li>
        )
      })}
    </ol>
  )
}
