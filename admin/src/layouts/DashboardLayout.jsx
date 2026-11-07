import { Outlet } from 'react-router-dom'
import Sidebar from '../components/Sidebar'
import Navbar from '../components/Navbar'
import SosBanner from '../components/SosBanner'
import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar'
import { useAdminAccess } from '../lib/AdminAccessContext'

export default function DashboardLayout() {
  const access = useAdminAccess()
  return (
    <SidebarProvider defaultOpen style={{ '--sidebar-width': '16rem' }}>
      <Sidebar />
      <SidebarInset className="h-svh overflow-hidden bg-slate-50">
        <Navbar breadcrumb={['SwiftServe', 'Dashboard']} />
        {access.can('sos.view') && <SosBanner />}
        <div className="flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8">
            <Outlet />
          </div>
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
