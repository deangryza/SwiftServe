// src/layouts/DashboardLayout.jsx
// Reusable shell: Sidebar + Navbar + page content (via <Outlet />).
// Every future dashboard page (User Management, Bookings, etc.) will render
// inside this layout once those routes are added.

import { useState } from 'react'
import { Outlet } from 'react-router-dom'
import { motion } from 'framer-motion'
import Sidebar from '../components/Sidebar'
import Navbar from '../components/Navbar'

export default function DashboardLayout() {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)

  return (
    <div className="flex min-h-screen overflow-hidden bg-surface-50 lg:h-screen">
      <Sidebar
        collapsed={collapsed}
        onToggle={() => setCollapsed((c) => !c)}
        mobileOpen={mobileOpen}
        onCloseMobile={() => setMobileOpen(false)}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <Navbar onOpenMobileSidebar={() => setMobileOpen(true)} breadcrumb={['SwiftServe', 'Dashboard']} />

        <motion.main
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.3 }}
          className="min-w-0 flex-1 overflow-x-hidden overflow-y-auto p-3 sm:p-5 lg:p-6 xl:p-8"
        >
          <Outlet />
        </motion.main>
      </div>
    </div>
  )
}
