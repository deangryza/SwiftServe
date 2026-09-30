// src/pages/Dashboard/DashboardHome.jsx
// Dashboard Overview — the landing page after login.
// Composed entirely from reusable components + static dummy data.

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

import { summaryStats, monthlyRegistrations, weeklyBookings, verificationStatus, systemHealth, quickActions } from '../../data/dashboardStats'
import { categories } from '../../data/categories'
import { latestBookings } from '../../data/bookings'
import { pendingWorkers } from '../../data/users'
import { recentReports } from '../../data/reports'
import { timelineEvents } from '../../data/timeline'

const HEALTH_ICONS = { Server, Radio, FileWarning, ShieldQuestion, Tag, Database, Plug }

function noop(label) {
  // Static demo action — every button performs a visible, harmless action.
  // eslint-disable-next-line no-alert
  alert(label)
}

export default function DashboardHome() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Dashboard Overview"
        breadcrumb={['SwiftServe', 'Dashboard', 'Overview']}
      />

      {/* Summary cards */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
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

        <ChartCard title="Service Categories" subtitle="Active listings by category">
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

        <ChartCard title="Weekly Bookings" subtitle="Bookings created per day, this week">
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
                  <button onClick={() => noop(`Viewing ${b.id}`)} className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-100">
                    <Eye size={13} /> View
                  </button>
                  <button onClick={() => noop(`Opening details for ${b.id}`)} className="inline-flex items-center gap-1 rounded-lg bg-swift-50 px-2.5 py-1 text-xs font-medium text-swift-600 hover:bg-swift-100">
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
                <StatusBadge status={w.idSubmitted ? 'Approved' : 'Pending'} />
              </td>
              <td className="whitespace-nowrap px-4 py-3">
                <StatusBadge status={w.faceVerified ? 'Approved' : 'Pending'} />
              </td>
              <td className="whitespace-nowrap px-4 py-3"><StatusBadge status={w.status} /></td>
              <td className="whitespace-nowrap px-4 py-3">
                <div className="flex gap-2">
                  <button onClick={() => noop(`Approved ${w.name}`)} className="inline-flex items-center gap-1 rounded-lg bg-success-50 px-2.5 py-1 text-xs font-medium text-success-600 hover:bg-success-100">
                    <Check size={13} /> Approve
                  </button>
                  <button onClick={() => noop(`Rejected ${w.name}`)} className="inline-flex items-center gap-1 rounded-lg bg-danger-50 px-2.5 py-1 text-xs font-medium text-danger-600 hover:bg-danger-100">
                    <X size={13} /> Reject
                  </button>
                  <button onClick={() => noop(`Reviewing ${w.name}`)} className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-100">
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
                  <button onClick={() => noop(`Resolved ${r.id}`)} className="inline-flex items-center gap-1 rounded-lg bg-success-50 px-2.5 py-1 text-xs font-medium text-success-600 hover:bg-success-100">
                    <CheckCircle2 size={13} /> Resolve
                  </button>
                  <button onClick={() => noop(`Viewing ${r.id}`)} className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-100">
                    <Eye size={13} /> View
                  </button>
                  <button onClick={() => noop(`Dismissed ${r.id}`)} className="inline-flex items-center gap-1 rounded-lg bg-surface-100 px-2.5 py-1 text-xs font-medium text-ink-600 hover:bg-surface-200">
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
            <QuickActionCard key={action.id} {...action} index={i} onClick={() => noop(`Opening ${action.title}`)} />
          ))}
        </div>
      </div>

      {/* Recent Activity + System Health */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <ChartCard title="Recent Activity" subtitle="Live feed of platform events" className="lg:col-span-2">
          <div className="max-h-[420px] overflow-y-auto pr-1">
            <Timeline events={timelineEvents} />
          </div>
        </ChartCard>

        <ChartCard title="System Health" subtitle="All systems operational">
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
