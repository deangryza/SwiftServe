import { Search } from 'lucide-react'
import { useState } from 'react'
import { Input } from '@/components/ui/input'

export default function SearchBar({ placeholder = 'Search users, bookings, workers…' }) {
  const [value, setValue] = useState('')

  return (
    <label className="relative hidden w-[min(26vw,22rem)] md:block">
      <span className="sr-only">Search the admin console</span>
      <Search className="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
      <Input
        type="search"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder={placeholder}
        className="h-9 bg-slate-50 pl-9"
      />
    </label>
  )
}
