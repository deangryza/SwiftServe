import { Outlet } from 'react-router-dom'
import Sidebar from '../components/Sidebar'
import Navbar from '../components/Navbar'
import { SidebarInset, SidebarProvider } from '@/components/ui/sidebar'

export default function DashboardLayout() {
  return (
    <SidebarProvider defaultOpen style={{ '--sidebar-width': '16rem' }}>
      <Sidebar />
      <SidebarInset className="h-svh overflow-hidden bg-slate-50">
        <Navbar breadcrumb={['SwiftServe', 'Dashboard']} />
        <div className="flex-1 overflow-y-auto">
          <div className="mx-auto w-full max-w-[1600px] p-4 sm:p-6 lg:p-8">
            <Outlet />
          </div>
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
