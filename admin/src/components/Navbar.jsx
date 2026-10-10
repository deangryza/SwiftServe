import { CalendarDays } from 'lucide-react'
import SearchBar from './SearchBar'
import NotificationDropdown from './NotificationDropdown'
import ProfileDropdown from './ProfileDropdown'
import { SidebarTrigger } from '@/components/ui/sidebar'

const formattedDate = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  year: 'numeric',
}).format(new Date())

export default function Navbar({ breadcrumb = ['Dashboard'] }) {
  return (
    <header className="sticky top-0 z-20 flex h-16 shrink-0 items-center gap-3 border-b bg-background/90 px-4 backdrop-blur-md sm:px-6">
      <SidebarTrigger className="size-10 md:hidden" />
      <nav aria-label="Breadcrumb" className="hidden text-sm text-muted-foreground sm:block">
        {breadcrumb.join(' / ')}
      </nav>

      <div className="ml-auto flex items-center gap-2 sm:gap-3">
        <SearchBar />
        <div className="hidden h-9 items-center gap-2 rounded-lg border bg-background px-3 text-xs font-medium text-muted-foreground lg:flex">
          <CalendarDays className="size-4" aria-hidden="true" />
          {formattedDate}
        </div>
        <NotificationDropdown />
        <div className="h-6 w-px bg-border" aria-hidden="true" />
        <ProfileDropdown />
      </div>
    </header>
  )
}
