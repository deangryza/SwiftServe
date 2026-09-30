// src/components/Sidebar.jsx
// Left navigation sidebar. Collapsible, highlights the active route, and
// shows the admin profile summary pinned to the bottom.

import { NavLink } from 'react-router-dom'
import { motion } from 'framer-motion'
import {
  LayoutDashboard, Users, ShieldCheck, CalendarCheck, FileWarning,
  LayoutGrid, Bell, BarChart3, History, Settings, UserCircle,
  ChevronsLeft, Radio,
} from 'lucide-react'

const NAV_ITEMS = [
  { to: '/dashboard', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/dashboard/users', label: 'User Management', icon: Users },
  { to: '/dashboard/verification', label: 'Worker Verification', icon: ShieldCheck },
  { to: '/dashboard/bookings', label: 'Booking Management', icon: CalendarCheck },
  { to: '/dashboard/reports', label: 'Reports & Complaints', icon: FileWarning },
  { to: '/dashboard/categories', label: 'Service Categories', icon: LayoutGrid },
  { to: '/dashboard/profile', label: 'Profile Setting', icon: UserCircle },
]

export default function Sidebar({ collapsed, onToggle, mobileOpen, onCloseMobile }) {
  return (
    <>
      {/* Mobile scrim */}
      {mobileOpen && (
        <div
          className="fixed inset-0 z-30 bg-ink-950/50 lg:hidden"
          onClick={onCloseMobile}
        />
      )}

      <motion.aside
        animate={{ width: collapsed ? 76 : 260 }}
        transition={{ duration: 0.25, ease: 'easeInOut' }}
        className={`fixed inset-y-0 left-0 z-40 flex flex-col bg-ink-900 text-surface-100 transition-transform duration-300 lg:static lg:translate-x-0 ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        {/* Brand */}
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-white/5 px-4">
          {!collapsed && (
            <div className="flex items-center gap-2">
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-swift-500">
                <Radio size={16} className="text-white" />
              </span>
              <span className="font-display text-sm font-bold tracking-tight text-white">SwiftServe</span>
            </div>
          )}
          {collapsed && (
            <span className="mx-auto flex h-8 w-8 items-center justify-center rounded-lg bg-swift-500">
              <Radio size={16} className="text-white" />
            </span>
          )}
        </div>

        {/* Nav items */}
        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
          {NAV_ITEMS.map((item) => {
            const Icon = item.icon
            return (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                title={collapsed ? item.label : undefined}
                className={({ isActive }) =>
                  `group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors duration-150 ${
                    isActive
                      ? 'bg-swift-500/15 text-gray-900'
                      : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
                  }`
                }
              >
                {({ isActive }) => (
                  <>
                    {isActive && (
                      <motion.span
                        layoutId="active-nav-pill"
                        className="absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-swift-400"
                      />
                    )}
                    <Icon size={18} className="shrink-0" />
                    {!collapsed && <span className="truncate">{item.label}</span>}
                  </>
                )}
              </NavLink>
            )
          })}
        </nav>

        {/* Collapse toggle (desktop only) */}
        <button
          onClick={onToggle}
          className="mx-3 mb-2 hidden items-center justify-center gap-2 rounded-xl border border-white/10 py-2 text-xs font-medium text-surface-100/60 hover:bg-white/5 hover:text-white lg:flex"
        >
          <ChevronsLeft size={15} className={`transition-transform duration-300 ${collapsed ? 'rotate-180' : ''}`} />
          {!collapsed && 'Collapse'}
        </button>

        {/* Admin profile footer */}
        <div className="border-t border-white/5 p-3">
          <div className={`flex items-center gap-3 rounded-xl px-2 py-2 ${!collapsed && 'hover:bg-white/5'}`}>
            <span className="relative flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-swift-400 to-violet-500 font-display text-xs font-bold text-white">
              RC
              <span className="absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full border-2 border-ink-900 bg-success-400" />
            </span>
            {!collapsed && (
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-white">Administrator</p>
                <p className="truncate text-xs text-surface-100/50">Super Admin</p>
              </div>
            )}
          </div>
        </div>
      </motion.aside>
    </>
  )
}
