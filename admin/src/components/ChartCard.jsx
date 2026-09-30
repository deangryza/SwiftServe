// src/components/ChartCard.jsx
// Consistent card wrapper used around every Recharts chart on the dashboard.

import { motion } from 'framer-motion'

export default function ChartCard({ title, subtitle, action, children, className = '' }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35 }}
      className={`rounded-2xl border border-surface-200 bg-white p-5 shadow-card ${className}`}
    >
      <div className="mb-4 flex items-start justify-between">
        <div>
          <h3 className="font-display text-sm font-semibold text-ink-900">{title}</h3>
          {subtitle && <p className="mt-0.5 text-xs text-ink-600/60">{subtitle}</p>}
        </div>
        {action}
      </div>
      {children}
    </motion.div>
  )
}
