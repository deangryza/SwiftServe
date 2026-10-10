import { NavLink, useLocation } from 'react-router-dom'
import {
  CalendarCheck,
  FileWarning,
  LayoutDashboard,
  LayoutGrid,
  ShieldCheck,
  UserCircle,
  Users,
} from 'lucide-react'
import Logo from './Logo'
import {
  Sidebar as SidebarPrimitive,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarSeparator,
  useSidebar,
} from '@/components/ui/sidebar'

const NAV_ITEMS = [
  { to: '/dashboard', label: 'Overview', icon: LayoutDashboard, end: true },
  { to: '/dashboard/users', label: 'User management', icon: Users },
  { to: '/dashboard/verification', label: 'Worker verification', icon: ShieldCheck, badge: 11 },
  { to: '/dashboard/bookings', label: 'Booking management', icon: CalendarCheck },
  { to: '/dashboard/reports', label: 'Reports & complaints', icon: FileWarning, badge: 9 },
  { to: '/dashboard/categories', label: 'Service categories', icon: LayoutGrid },
  { to: '/dashboard/profile', label: 'Profile settings', icon: UserCircle },
]

function routeIsActive(pathname, item) {
  return item.end ? pathname === item.to : pathname.startsWith(item.to)
}

export default function Sidebar() {
  const { pathname } = useLocation()
  const { isMobile, setOpenMobile } = useSidebar()

  return (
    <SidebarPrimitive collapsible="offcanvas" className="border-sidebar-border">
      <SidebarHeader className="h-16 justify-center border-b border-sidebar-border px-4">
        <Logo variant="light" />
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup className="px-3 py-4">
          <SidebarGroupLabel className="px-2 text-[11px] font-semibold uppercase tracking-[0.12em] text-sidebar-foreground/55">
            Workspace
          </SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu className="gap-1">
              {NAV_ITEMS.map((item) => {
                const Icon = item.icon
                const isActive = routeIsActive(pathname, item)
                return (
                  <SidebarMenuItem key={item.to}>
                    <SidebarMenuButton
                      isActive={isActive}
                      tooltip={item.label}
                      className="h-10 rounded-lg px-3 text-sidebar-foreground/75 hover:bg-white/10 hover:text-white data-active:bg-white/12 data-active:text-white"
                      render={(
                        <NavLink
                          to={item.to}
                          end={item.end}
                          onClick={() => isMobile && setOpenMobile(false)}
                        />
                      )}
                    >
                      <Icon aria-hidden="true" />
                      <span>{item.label}</span>
                    </SidebarMenuButton>
                    {item.badge && (
                      <SidebarMenuBadge className="right-2 bg-white/10 text-sidebar-foreground">
                        {item.badge}
                      </SidebarMenuBadge>
                    )}
                  </SidebarMenuItem>
                )
              })}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarSeparator />
      <SidebarFooter className="p-3">
        <div className="flex items-center gap-3 rounded-xl bg-white/[0.07] p-2.5">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-xs font-semibold text-white">
            RC
          </span>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">Administrator</p>
            <p className="truncate text-xs text-sidebar-foreground/55">Super Admin</p>
          </div>
          <span className="ml-auto size-2 rounded-full bg-success-400" aria-label="Online" />
        </div>
      </SidebarFooter>
    </SidebarPrimitive>
  )
}
