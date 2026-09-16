// src/components/StatusBadge.jsx
// Small colored pill used across tables to show a status value.
// Colors map to the semantic tokens defined in tailwind.config.js.

const STATUS_STYLES = {
  Verified: 'bg-success-50 text-success-600',
  Active: 'bg-success-50 text-success-600',
  Completed: 'bg-success-50 text-success-600',
  Resolved: 'bg-success-50 text-success-600',
  Approved: 'bg-success-50 text-success-600',

  Pending: 'bg-warning-50 text-warning-600',
  Ongoing: 'bg-swift-50 text-swift-600',
  'Under Review': 'bg-warning-50 text-warning-600',

  Rejected: 'bg-danger-50 text-danger-600',
  Cancelled: 'bg-danger-50 text-danger-600',
  Suspended: 'bg-danger-50 text-danger-600',
  Open: 'bg-danger-50 text-danger-600',
  Dismissed: 'bg-surface-200 text-ink-600',
}

export default function StatusBadge({ status }) {
  const style = STATUS_STYLES[status] || 'bg-surface-200 text-ink-700'
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium ${style}`}>
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {status}
    </span>
  )
}
