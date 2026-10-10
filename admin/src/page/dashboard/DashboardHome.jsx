import { useNavigate } from 'react-router-dom'
import {
  ArrowRight,
  CalendarClock,
  FileWarning,
  ShieldCheck,
  UsersRound,
} from 'lucide-react'
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import StatusBadge from '../../components/StatusBadge'
import useAdminData from '../../lib/useAdminData'
import DataState from '../../components/DataState'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'


const toneStyles = {
  primary: {
    icon: 'bg-primary-50 text-primary-700',
    detail: 'bg-primary-50 text-primary-700',
    bar: 'bg-primary-600',
  },
  warning: {
    icon: 'bg-warning-50 text-warning-600',
    detail: 'bg-warning-50 text-warning-600',
    bar: 'bg-warning-500',
  },
  danger: {
    icon: 'bg-danger-50 text-danger-600',
    detail: 'bg-danger-50 text-danger-600',
    bar: 'bg-danger-500',
  },
  success: {
    icon: 'bg-success-50 text-success-600',
    detail: 'bg-success-50 text-success-600',
    bar: 'bg-success-500',
  },
}


const formattedDate = new Intl.DateTimeFormat('en-US', {
  weekday: 'long',
  month: 'long',
  day: 'numeric',
}).format(new Date())

function PriorityMetric({ metric }) {
  const Icon = metric.icon
  const styles = toneStyles[metric.tone]

  return (
    <Card className="gap-0 overflow-hidden py-0 shadow-card ring-1 ring-slate-200">
      <CardContent className="p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="text-sm font-medium text-muted-foreground">{metric.title}</p>
            <p className="mt-2 text-3xl font-semibold tracking-[-0.04em] text-slate-950">{metric.value}</p>
          </div>
          <span className={`flex size-10 items-center justify-center rounded-xl ${styles.icon}`}>
            <Icon className="size-5" aria-hidden="true" />
          </span>
        </div>
        <Badge variant="secondary" className={`mt-3 ${styles.detail}`}>{metric.detail}</Badge>
        <div className="mt-4 h-1.5 overflow-hidden rounded-full bg-slate-100" aria-hidden="true">
          <span className={`block h-full rounded-full ${styles.bar}`} style={{ width: `${metric.progress}%` }} />
        </div>
      </CardContent>
    </Card>
  )
}

function AttentionQueue({ attentionItems }) {
  const navigate = useNavigate()

  return (
    <Card className="gap-0 py-0 shadow-card ring-1 ring-slate-200">
      <CardHeader className="border-b px-5 py-4">
        <CardTitle>Needs attention</CardTitle>
        <CardDescription>Work waiting for an administrator</CardDescription>
      </CardHeader>
      <CardContent className="px-5 py-1">
        {attentionItems.map((item) => (
          <div key={item.title} className="flex items-center gap-3 border-b py-4 last:border-0">
            <span className={`size-2 rounded-full ${toneStyles[item.tone].bar}`} aria-hidden="true" />
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-slate-900">{item.title}</p>
              <p className="mt-0.5 text-xs text-muted-foreground">{item.description}</p>
            </div>
            <Badge variant="secondary" className={toneStyles[item.tone].detail}>{item.count}</Badge>
            <Button type="button" variant="ghost" size="icon-sm" onClick={() => navigate(item.route)} aria-label={`Open ${item.title}`}>
              <ArrowRight aria-hidden="true" />
            </Button>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}

export default function DashboardHome() {
  const navigate = useNavigate()
  const { data, loading, error } = useAdminData('overview', { users: [], bookings: [], reports: [], categories: [], verifications: [] })
  const { bookings, reports, verifications } = data
  const pending = verifications.filter(item => ['pending', 'under_review'].includes(item.status)).length
  const verified = verifications.filter(item => item.status === 'verified').length
  const openReports = reports.filter(item => ['Pending', 'Under Review'].includes(item.status))
  const activeBookings = bookings.filter(item => ['Accepted', 'Ongoing'].includes(item.status)).length
  const ratio = (value, total) => total ? Math.round(value / total * 100) : 0
  const priorityMetrics = [
    { title: 'Active bookings', value: activeBookings, detail: 'Accepted or ongoing', progress: ratio(activeBookings, bookings.length), icon: CalendarClock, tone: 'primary' },
    { title: 'Pending verification', value: pending, detail: 'Needs review', progress: ratio(pending, verifications.length), icon: ShieldCheck, tone: 'warning' },
    { title: 'Open reports', value: openReports.length, detail: openReports.filter(item => item.priority === 'High').length + ' marked urgent', progress: ratio(openReports.length, reports.length), icon: FileWarning, tone: 'danger' },
    { title: 'Verified workers', value: verified, detail: 'Completed verification', progress: ratio(verified, verifications.length), icon: UsersRound, tone: 'success' },
  ]
  const attentionItems = [
    { title: 'Worker verification', description: 'ID and face review', count: pending, route: '/dashboard/verification', tone: 'warning' },
    { title: 'Open complaints', description: 'Pending or under review', count: openReports.length, route: '/dashboard/reports', tone: 'danger' },
    { title: 'Pending bookings', description: 'Awaiting assignment or response', count: bookings.filter(item => item.status === 'Pending').length, route: '/dashboard/bookings', tone: 'primary' },
  ]
  const latestBookings = bookings.slice(0, 5).map(item => ({ ...item, client: item.clientName, worker: item.providerName }))
  const weeklyBookings = Array.from({ length: 7 }, (_, index) => {
    const date = new Date(); date.setDate(date.getDate() - 6 + index)
    return { day: date.toLocaleDateString('en-US', { weekday: 'short' }), bookings: bookings.filter(item => new Date(item.createdAt).toDateString() === date.toDateString()).length }
  })
  if (loading || error) return <DataState loading={loading} error={error} />

  return (
    <div className="space-y-5 sm:space-y-6">
      <header className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-sm font-medium text-primary-700">Operations overview</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-[-0.035em] text-slate-950 sm:text-3xl">Dashboard</h1>
          <p className="mt-1 text-sm text-muted-foreground">{formattedDate} · Saved records ? refreshed every 30 seconds</p>
        </div>
        <Button type="button" size="lg" className="h-10 self-start bg-primary-600 text-white hover:bg-primary-700" onClick={() => navigate('/dashboard/verification')}>
          Review {pending} workers
          <ArrowRight data-icon="inline-end" aria-hidden="true" />
        </Button>
      </header>

      <section aria-label="Priority platform metrics" className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {priorityMetrics.map((metric) => <PriorityMetric key={metric.title} metric={metric} />)}
      </section>

      <section className="grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1.65fr)_minmax(20rem,1fr)]">
        <Card className="gap-0 py-0 shadow-card ring-1 ring-slate-200">
          <CardHeader className="flex-row items-start justify-between border-b px-5 py-4">
            <div>
              <CardTitle>Booking volume</CardTitle>
              <CardDescription>Bookings created during the last seven days</CardDescription>
            </div>
            <Button type="button" variant="ghost" size="sm" onClick={() => navigate('/dashboard/bookings')}>View bookings</Button>
          </CardHeader>
          <CardContent className="p-4 sm:p-5">
            <div className="h-[260px] w-full" role="img" aria-label={weeklyBookings.map(item => `${item.day}: ${item.bookings} bookings`).join(', ')}>
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={weeklyBookings} accessibilityLayer margin={{ top: 8, right: 8, left: -24, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--color-slate-200)" />
                  <XAxis dataKey="day" tick={{ fontSize: 12, fill: 'var(--color-slate-500)' }} axisLine={false} tickLine={false} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: 'var(--color-slate-500)' }} axisLine={false} tickLine={false} />
                  <Tooltip cursor={{ fill: 'var(--color-slate-100)' }} contentStyle={{ borderRadius: 10, borderColor: 'var(--border)', boxShadow: 'var(--shadow-card)' }} />
                  <Bar dataKey="bookings" name="Bookings" fill="var(--color-primary-600)" radius={[6, 6, 0, 0]} maxBarSize={42} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        <AttentionQueue attentionItems={attentionItems} />
      </section>

      <Card className="gap-0 overflow-hidden py-0 shadow-card ring-1 ring-slate-200">
        <CardHeader className="flex-row items-start justify-between border-b px-5 py-4">
          <div>
            <CardTitle>Latest bookings</CardTitle>
            <CardDescription>Most recent booking activity across the platform</CardDescription>
          </div>
          <Button type="button" variant="ghost" size="sm" onClick={() => navigate('/dashboard/bookings')}>View all</Button>
        </CardHeader>
        <Table>
          <TableHeader>
            <TableRow className="bg-slate-50 hover:bg-slate-50">
              <TableHead className="pl-5">Booking</TableHead>
              <TableHead>Client</TableHead>
              <TableHead className="hidden md:table-cell">Worker</TableHead>
              <TableHead className="hidden lg:table-cell">Service</TableHead>
              <TableHead className="hidden sm:table-cell">Schedule</TableHead>
              <TableHead>Status</TableHead>
              <TableHead><span className="sr-only">Actions</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {latestBookings.length === 0 && <TableRow><TableCell colSpan={7} className="py-8 text-center text-muted-foreground">No bookings yet.</TableCell></TableRow>}
            {latestBookings.slice(0, 5).map((booking) => (
              <TableRow key={booking.id}>
                <TableCell className="pl-5 font-mono text-xs font-medium text-slate-700">{booking.id}</TableCell>
                <TableCell className="font-medium text-slate-900">{booking.client}</TableCell>
                <TableCell className="hidden text-slate-600 md:table-cell">{booking.worker}</TableCell>
                <TableCell className="hidden text-slate-600 lg:table-cell">{booking.category}</TableCell>
                <TableCell className="hidden font-mono text-xs text-slate-500 sm:table-cell">{booking.schedule}</TableCell>
                <TableCell><StatusBadge status={booking.status} /></TableCell>
                <TableCell className="pr-5 text-right">
                  <Button type="button" variant="ghost" size="sm" onClick={() => navigate('/dashboard/bookings')} aria-label={`View ${booking.id}`}>
                    View
                  </Button>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>
    </div>
  )
}
