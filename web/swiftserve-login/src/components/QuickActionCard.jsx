// src/components/QuickActionCard.jsx
// Large shortcut button used in the Quick Actions section of Dashboard Home.

import { motion } from 'framer-motion'
import * as Icons from 'lucide-react'

const COLOR_MAP = {
  swift: 'bg-swift-50 text-swift-600',
  success: 'bg-success-50 text-success-600',
  warning: 'bg-warning-50 text-warning-600',
  violet: 'bg-violet-50 text-violet-500',
  danger: 'bg-danger-50 text-danger-600',
}

export default function QuickActionCard({ title, description, icon, color = 'swift', onClick, index = 0 }) {
  const Icon = Icons[icon] || Icons.Zap
  const palette = COLOR_MAP[color] || COLOR_MAP.swift

  return (
    <motion.button
      type="button"
      onClick={onClick}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: index * 0.05 }}
      whileHover={{ y: -3, scale: 1.01 }}
      whileTap={{ scale: 0.98 }}
      className="group flex items-start gap-3.5 rounded-2xl border border-surface-200 bg-white p-4 text-left shadow-card transition-shadow hover:shadow-card-hover"
    >
      <div className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${palette}`}>
        <Icon size={20} />
      </div>
      <div className="min-w-0">
        <p className="font-display text-sm font-semibold text-ink-900">{title}</p>
        <p className="mt-0.5 text-xs leading-relaxed text-ink-600/60">{description}</p>
      </div>
    </motion.button>
  )
}
