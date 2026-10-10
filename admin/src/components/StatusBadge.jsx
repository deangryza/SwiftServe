import { Badge } from '@/components/ui/badge'

const STATUS_STYLES = {
  Verified: 'bg-success-50 text-success-600',
  Active: 'bg-success-50 text-success-600',
  Completed: 'bg-success-50 text-success-600',
  Resolved: 'bg-success-50 text-success-600',
  Approved: 'bg-success-50 text-success-600',
  Pending: 'bg-warning-50 text-warning-600',
  Ongoing: 'bg-primary-50 text-primary-700',
  'Under Review': 'bg-warning-50 text-warning-600',
  Rejected: 'bg-danger-50 text-danger-600',
  Cancelled: 'bg-danger-50 text-danger-600',
  Suspended: 'bg-danger-50 text-danger-600',
  Open: 'bg-danger-50 text-danger-600',
  Dismissed: 'bg-slate-100 text-slate-600',
}

export default function StatusBadge({ status }) {
  return (
    <Badge variant="secondary" className={STATUS_STYLES[status] || 'bg-slate-100 text-slate-700'}>
      <span className="size-1.5 rounded-full bg-current" aria-hidden="true" />
      {status}
    </Badge>
  )
}
