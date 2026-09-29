// src/components/StatCard.jsx
// Summary card used on the Dashboard Home grid (Total Users, Verified Workers, etc).
// Shows an icon, title, big value, percentage change, and a colored trend indicator.

import { motion } from 'framer-motion'
import * as Icons from 'lucide-react'
import { ArrowUpRight, ArrowDownRight } from 'lucide-react'

const COLOR_MAP = {
  swift: { bg: 'bg-swift-50', text: 'text-swift-600', ring: 'ring-swift-100' },
  success: { bg: 'bg-success-50', text: 'text-success-600', ring: 'ring-success-50' },
  warning: { bg: 'bg-warning-50', text: 'text-warning-600', ring: 'ring-warning-50' },
  violet: { bg: 'bg-violet-50', text: 'text-violet-500', ring: 'ring-violet-50' },
  danger: { bg: 'bg-danger-50', text: 'text-danger-600', ring: 'ring-danger-50' },
}

export default function StatCard({ title, value, change, trend, icon, color = 'swift', index = 0 }) {
  const Icon = Icons[icon] || Icons.Circle
  const palette = COLOR_MAP[color] || COLOR_MAP.swift
  const isUp = trend === 'up'

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35, delay: index * 0.04 }}
      whileHover={{ y: -3 }}
      className="group relative overflow-hidden rounded-2xl border border-surface-200 bg-white p-5 shadow-card transition-shadow duration-200 hover:shadow-card-hover"
    >
      <div className="flex items-start justify-between">
        <div className={`flex h-10 w-10 items-center justify-center rounded-xl ${palette.bg} ${palette.text}`}>
          <Icon size={20} strokeWidth={2} />
        </div>
        <span
          className={`inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-xs font-semibold ${
            isUp ? 'bg-success-50 text-success-600' : 'bg-danger-50 text-danger-600'
          }`}
        >
          {isUp ? <ArrowUpRight size={13} /> : <ArrowDownRight size={13} />}
          {change}
        </span>
      </div>

      <p className="mt-4 text-sm font-medium text-ink-600/70">{title}</p>
      <p className="mt-1 font-display text-2xl font-bold tracking-tight text-ink-900">{value}</p>

      {/* Signature accent line — animates on hover, reinforces the "live dispatch" identity */}
      <div className={`absolute inset-x-0 bottom-0 h-0.5 origin-left scale-x-0 ${palette.text.replace('text-', 'bg-')} transition-transform duration-300 group-hover:scale-x-100`} />
    </motion.div>
  )
}
