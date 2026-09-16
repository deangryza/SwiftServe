// src/components/PageHeader.jsx
// Page title + breadcrumb, used at the top of every dashboard page.

import { ChevronRight } from 'lucide-react'
import { motion } from 'framer-motion'

export default function PageHeader({ title, breadcrumb = [], action }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: -6 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
      className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
    >
      <div>
        <nav className="mb-1 flex items-center gap-1.5 text-xs text-ink-600/50">
          {breadcrumb.map((crumb, i) => (
            <span key={crumb} className="flex items-center gap-1.5">
              {i > 0 && <ChevronRight size={12} />}
              <span className={i === breadcrumb.length - 1 ? 'font-medium text-ink-600' : ''}>{crumb}</span>
            </span>
          ))}
        </nav>
        <h1 className="font-display text-xl font-bold tracking-tight text-ink-900 sm:text-2xl">{title}</h1>
      </div>
      {action}
    </motion.div>
  )
}
