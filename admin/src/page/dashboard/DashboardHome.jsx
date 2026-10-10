// src/pages/Dashboard/DashboardHome.jsx
// Dashboard Overview — the landing page after login.
// Overview derived from protected Firestore-backed API responses.

import {
  BarChart, Bar, PieChart, Pie, Cell, LineChart, Line,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
} from 'recharts'
import { motion } from 'framer-motion'
import { Eye, FileText, Check, X, ClipboardCheck, CheckCircle2, XCircle, Server, Radio, FileWarning, ShieldQuestion, Tag, Database, Plug } from 'lucide-react'

import PageHeader from '../../components/PageHeader'
import StatCard from '../../components/StatCard'
import ChartCard from '../../components/ChartCard'
import DataTable from '../../components/DataTable'
import StatusBadge from '../../components/StatusBadge'
import QuickActionCard from '../../components/QuickActionCard'
import Timeline from '../../components/Timeline'

import { useNavigate } from 'react-router-dom';
import useAdminData from '../../lib/useAdminData';
import DataState from '../../components/DataState';

const HEALTH_ICONS = { Server, Radio, FileWarning, ShieldQuestion, Tag, Database, Plug }

export default function DashboardHome() {
  const navigate = useNavigate();
  const { data, loading, error } = useAdminData('overview', { users: [], bookings: [], reports: [], categories: [], verifications: [] });
  const { users, bookings, reports, verifications } = data;
  const count = (items, status) => items.filter(item => item.status === status).length;
  const verified = count(verifications, 'verified');
  const pending = count(verifications, 'pending') + count(verifications, 'under_review');
  const summaryStats = [
    ['total-users', 'Total Users', users.length, 'Users', 'swift'],
    ['verified-workers', 'Verified Workers', verified, 'ShieldCheck', 'success'],
    ['pending-verification', 'Pending Verification', pending, 'Clock', 'warning'],
    ['active-bookings', 'Active Bookings', bookings.filter(b => ['Accepted', 'Ongoing'].includes(b.status)).length, 'CalendarClock', 'violet'],
    ['completed-jobs', 'Completed Jobs', count(bookings, 'Completed'), 'CheckCircle2', 'success'],
    ['cancelled-jobs', 'Cancelled Jobs', count(bookings, 'Cancelled'), 'XCircle', 'danger'],
    ['reports', 'Reports Received', reports.length, 'FileWarning', 'warning'],
    ['resolved', 'Resolved Complaints', count(reports, 'Resolved'), 'BadgeCheck', 'swift'],
  ].map(([id, title, value, icon, color]) => ({ id, title, value, icon, color }));
  const monthlyRegistrations = Array.from({ length: 8 }, (_, index) => {
    const date = new Date(); date.setDate(1); date.setMonth(date.getMonth() - 7 + index);
    return { month: date.toLocaleString('en', { month: 'short' }), users: users.filter(user => { const created = new Date(user.createdAt); return created.getMonth() === date.getMonth() && created.getFullYear() === date.getFullYear(); }).length };
  });
  const weeklyBookings = Array.from({ length: 7 }, (_, index) => {
    const date = new Date(); date.setDate(date.getDate() - 6 + index);
    return { day: date.toLocaleString('en', { weekday: 'short' }), bookings: bookings.filter(booking => new Date(booking.createdAt).toDateString() === date.toDateString()).length };
  });
  const categoryNames = [...new Set([...data.categories.map(c => c.name), ...users.filter(u => u.role === 'Worker').map(u => u.category)].filter(Boolean))];
  const categories = categoryNames.map((name, index) => ({ name, value: users.filter(u => u.role === 'Worker' && u.category === name).length, color: ['#2F6FED', '#12B76A', '#F59E0B', '#6D4FEA'][index % 4] }));
  const verificationStatus = [{ name: 'Verified', value: verified, color: '#12B76A' }, { name: 'Pending', value: pending, color: '#F59E0B' }, { name: 'Rejected', value: count(verifications, 'rejected'), color: '#F04438' }];
  const latestBookings = bookings.slice(0, 5).map(b => ({ ...b, client: b.clientName, worker: b.providerName }));
  const pendingWorkers = verifications.filter(v => ['pending', 'under_review'].includes(v.status)).map(v => ({ ...v, name: users.find(u => u.id === v.id)?.name || v.id, status: 'Pending' }));
  const recentReports = reports.slice(0, 5);
  const timelineEvents = [...users.filter(u => u.createdAt).map(u => ({ id: 'user-' + u.id, type: 'worker_registered', text: u.name + ' registered', time: u.createdAt })), ...bookings.filter(b => b.createdAt).map(b => ({ id: 'booking-' + b.id, type: 'booking_created', text: b.serviceTitle + ' requested', time: b.createdAt }))].sort((a, b) => b.time.localeCompare(a.time)).slice(0, 10);
  const systemHealth = [{ label: 'Database', value: 'Connected', icon: 'Database' }, { label: 'Admin API', value: 'Connected', icon: 'Plug' }, { label: 'Pending Reports', value: count(reports, 'Pending'), icon: 'FileWarning' }];
  const quickActions = [{ id: 'verification', title: 'Review Workers', description: 'Review submitted verification', icon: 'UserCheck', color: 'success' }, { id: 'users', title: 'Manage Users', description: 'Manage registered accounts', icon: 'Users', color: 'swift' }, { id: 'reports', title: 'View Reports', description: 'Review complaints', icon: 'FileWarning', color: 'warning' }, { id: 'bookings', title: 'Bookings', description: 'Manage service requests', icon: 'CalendarClock', color: 'violet' }];
  if (loading || error) return <DataState loading={loading} error={error} />;
  return (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard Overview"
        breadcrumb={['SwiftServe', 'Dashboard', 'Overview']}
      />

      {/* Summary cards */}
      <div className="grid grid-cols-1 gap-3 min-[420px]:grid-cols-2 sm:gap-4 lg:grid-cols-4">
        {summaryStats.map((stat, i) => (
          <StatCard key={stat.id} {...stat} index={i} />
        ))}
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <ChartCard title="Monthly User Registrations" subtitle="New sign-ups over the last 8 months">
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={monthlyRegistrations}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#E4E8F0" />
              <XAxis dataKey="month" tick={{ fontSize: 12, fill: '#6B7690' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 12, fill: '#6B7690' }} axisLine={false} tickLine={false} />
              <Tooltip cursor={{ fill: '#F1F3F7' }} contentStyle={{ borderRadius: 12, border: '1px solid #E4E8F0', fontSize: 12 }} />
              <Bar dataKey="users" fill="#2F6FED" radius={[6, 6, 0, 0]} maxBarSize={36} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard title="Service Categories" subtitle="Registered workers by category">
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie data={categories} dataKey="value" nameKey="name" innerRadius={0} outerRadius={95} paddingAngle={1}>
                {categories.map((c) => (
                  <Cell key={c.name} fill={c.color} />
                ))}
              </Pie>
              <Tooltip contentStyle={{ borderRadius: 12, border: '1px solid #E4E8F0', fontSize: 12 }} />
            </PieChart>
          </ResponsiveContainer>
          <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1.5">
            {categories.slice(0, 6).map((c) => (
              <span key={c.name} className="flex items-center gap-1.5 text-[11px] text-ink-600/60">
                <span className="h-2 w-2 rounded-full" style={{ backgroundColor: c.color }} />
                {c.name}
              </span>
            ))}
          </div>
        </ChartCard>

        <ChartCard title="Weekly Bookings" subtitle="Bookings created per day, last 7 days">
          <ResponsiveContainer width="100%" height={260}>
            <LineChart data={weeklyBookings}>
              <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#E4E8F0" />
              <XAxis dataKey="day" tick={{ fontSize: 12, fill: '#6B7690' }} axisLine={false} tickLine={false} />
              <YAxis tick={{ fontSize: 12, fill: '#6B7690' }} axisLine={false} tickLine={false} />
              <Tooltip contentStyle={{ borderRadius: 12, border: '1px solid #E4E8F0', fontSize: 12 }} />
              <Line type="monotone" dataKey="bookings" stroke="#6D4FEA" strokeWidth={2.5} dot={{ r: 3, fill: '#6D4FEA' }} activeDot={{ r: 5 }} />
            </LineChart>
          </ResponsiveContainer>
        </ChartCard>

        <ChartCard title="Worker Verification Status" subtitle="Current standing across all workers">
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie data={verificationStatus} dataKey="value" nameKey="name" innerRadius={64} outerRadius={95} paddingAngle={2}>
                {verificationStatus.map((c) => (
                  <Cell key={c.name} fill={c.color} />
                ))}
              </Pie>
              <Tooltip contentStyle={{ borderRadius: 12, border: '1px solid #E4E8F0', fontSize: 12 }} />
              <Legend verticalAlign="bottom" height={32} iconType="circle" wrapperStyle={{ fontSize: 12 }} />
            </PieChart>
          </ResponsiveContainer>
        </ChartCard>
      </div>

      {/* Latest Bookings table */}
      <ChartCard title="Latest Bookings" subtitle="Most recent booking activity across the platform">
        <DataTable columns={['Booking ID', 'Client', 'Worker', 'Category', 'Schedule', 'Status', 'Action']}>
          {latestBookings.map((b) => (
            <tr key={b.id} className="transition-colors hover:bg-surface-50">
              <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-ink-700">{b.id}</td>
              <td className="whitespace-nowrap px-4 py-3 text-ink-800">{b.client}</td>
              <td className="whitespace-nowrap px-4 py-3 text-ink-800">{b.worker}</td>
              <td className="whitespace-nowrap px-4 py-3 text-ink-600">{b.category}</td>
              <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-ink-600">{b.schedule}</td>
              <td className="whitespace-nowrap px-4 py-3"><StatusBadge status={b.status} /></td>
              <td className="whitespace-nowrap px-4 py-3">
                <div className="flex gap-2">
                  <button onClick={() => navigate('/dashboard/bookings')} className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-100">
                    <Eye size={13} /> View
                  </button>
                  <button onClick={() => navigate('/dashboard/bookings')} className="inline-flex items-center gap-1 rounded-lg bg-swift-50 px-2.5 py-1 text-xs font-medium text-swift-600 hover:bg-swift-100">
                    <FileText size={13} /> Details
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </DataTable>
      </ChartCard>

      {/* Pending Worker Verification table */}
      <ChartCard title="Pending Worker Verification" subtitle="Workers awaiting ID and face verification review">
        <DataTable columns={['Worker', 'Submitted ID', 'Face Verification', 'Status', 'Actions']}>
          {pendingWorkers.map((w) => (
            <tr key={w.id} className="transition-colors hover:bg-surface-50">
              <td className="whitespace-nowrap px-4 py-3">
                <p className="text-ink-800">{w.name}</p>
                <p className="font-mono text-[11px] text-ink-600/50">{w.id}</p>
              </td>
              <td className="whitespace-nowrap px-4 py-3">
                <StatusBadge status={w.idSubmitted ? 'Submitted' : 'Not recorded'} />
              </td>
              <td className="whitespace-nowrap px-4 py-3">
                <StatusBadge status={w.faceVerified == null ? 'Not recorded' : w.faceVerified ? 'Verified' : 'Not verified'} />
              </td>
              <td className="whitespace-nowrap px-4 py-3"><StatusBadge status={w.status} /></td>
              <td className="whitespace-nowrap px-4 py-3">
                <div className="flex gap-2">
                  <button onClick={() => navigate('/dashboard/verification')} className="inline-flex items-center gap-1 rounded-lg bg-success-50 px-2.5 py-1 text-xs font-medium text-success-600 hover:bg-success-100">
                    <Check size={13} /> Approve
                  </button>
                  <button onClick={() => navigate('/dashboard/verification')} className="inline-flex items-center gap-1 rounded-lg bg-danger-50 px-2.5 py-1 text-xs font-medium text-danger-600 hover:bg-danger-100">
                    <X size={13} /> Reject
                  </button>
                  <button onClick={() => navigate('/dashboard/verification')} className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-100">
                    <ClipboardCheck size={13} /> Review
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </DataTable>
      </ChartCard>

      {/* Recent Reports table */}
      <ChartCard title="Recent Reports" subtitle="Latest complaints filed by clients and workers">
        <DataTable columns={['Reporter', 'Reported User', 'Reason', 'Status', 'Date', 'Actions']}>
          {recentReports.map((r) => (
            <tr key={r.id} className="transition-colors hover:bg-surface-50">
              <td className="whitespace-nowrap px-4 py-3 text-ink-800">{r.reporter}</td>
              <td className="whitespace-nowrap px-4 py-3 text-ink-800">{r.reportedUser}</td>
              <td className="whitespace-nowrap px-4 py-3 text-ink-600">{r.reason}</td>
              <td className="whitespace-nowrap px-4 py-3"><StatusBadge status={r.status} /></td>
              <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-ink-600">{r.date}</td>
              <td className="whitespace-nowrap px-4 py-3">
                <div className="flex gap-2">
                  <button onClick={() => navigate('/dashboard/reports')} className="inline-flex items-center gap-1 rounded-lg bg-success-50 px-2.5 py-1 text-xs font-medium text-success-600 hover:bg-success-100">
                    <CheckCircle2 size={13} /> Resolve
                  </button>
                  <button onClick={() => navigate('/dashboard/reports')} className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-100">
                    <Eye size={13} /> View
                  </button>
                  <button onClick={() => navigate('/dashboard/reports')} className="inline-flex items-center gap-1 rounded-lg bg-surface-100 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-200">
                    <XCircle size={13} /> Dismiss
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </DataTable>
      </ChartCard>

      {/* Quick Actions */}
      <div>
        <h2 className="mb-3 font-display text-sm font-semibold text-ink-900">Quick Actions</h2>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {quickActions.map((action, i) => (
            <QuickActionCard key={action.id} {...action} index={i} onClick={() => navigate('/dashboard/' + action.id)} />
          ))}
        </div>
      </div>

      {/* Recent Activity + System Health */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <ChartCard title="Recent Activity" subtitle="Recent saved records; refreshed every 30 seconds" className="lg:col-span-2">
          <div className="max-h-[420px] overflow-y-auto pr-1">
            <Timeline events={timelineEvents} />
          </div>
        </ChartCard>

        <ChartCard title="System Health" subtitle="Database connection verified">
          <ul className="space-y-3">
            {systemHealth.map((item, i) => {
              const Icon = HEALTH_ICONS[item.icon]
              return (
                <motion.li
                  key={item.label}
                  initial={{ opacity: 0, x: 8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.25, delay: i * 0.03 }}
                  className="flex items-center justify-between rounded-xl border border-surface-200 px-3 py-2.5"
                >
                  <div className="flex items-center gap-2.5">
                    <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-success-50 text-success-600">
                      <Icon size={14} />
                    </span>
                    <span className="text-sm text-ink-700">{item.label}</span>
                  </div>
                  <div className="flex items-center gap-1.5">
                    <span className="relative flex h-2 w-2">
                      <span className="absolute inline-flex h-full w-full animate-ring rounded-full bg-success-400" />
                      <span className="relative inline-flex h-2 w-2 rounded-full bg-success-500 animate-pulseDot" />
                    </span>
                    <span className="text-xs font-semibold text-success-600">{item.value}</span>
                  </div>
                </motion.li>
              )
            })}
          </ul>
        </ChartCard>
      </div>
    </div>
  )
}
