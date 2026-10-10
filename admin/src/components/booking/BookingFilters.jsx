import { Search, X } from "lucide-react";
import { STATUS } from "../../data/bookings";

export default function BookingFilters({
  categories = [],
  searchTerm,
  onSearchChange,
  statusFilter,
  onStatusChange,
  categoryFilter,
  onCategoryChange,
  dateFilter,
  onDateChange,
  onClearFilters,
}) {
  const statusOptions = ["All", ...new Set(Object.values(STATUS))];
  const categoryOptions = ["All", ...categories];

  return (
    <div className="mb-6 rounded-2xl border border-gray-100 bg-white p-3 shadow-sm sm:p-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-[minmax(240px,1fr)_auto_auto_auto_auto] xl:items-center">
        {/* Search */}
        <div className="relative min-w-0 sm:col-span-2 xl:col-span-1">
          <Search
            size={18}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
          />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search by booking ID, client, provider, or service..."
            className="w-full pl-10 pr-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
          />
        </div>

        {/* Status filter */}
        <select
          value={statusFilter}
          onChange={(e) => onStatusChange(e.target.value)}
          className="w-full rounded-xl border border-gray-200 px-3 py-2.5 text-sm text-gray-700 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-500/40"
        >
          {statusOptions.map((opt) => (
            <option key={opt} value={opt}>
              {opt === "All" ? "All Statuses" : opt}
            </option>
          ))}
        </select>

        {/* Category filter */}
        <select
          value={categoryFilter}
          onChange={(e) => onCategoryChange(e.target.value)}
          className="w-full rounded-xl border border-gray-200 px-3 py-2.5 text-sm text-gray-700 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-500/40"
        >
          {categoryOptions.map((opt) => (
            <option key={opt} value={opt}>
              {opt === "All" ? "All Categories" : opt}
            </option>
          ))}
        </select>

        {/* Date filter */}
        <input
          type="date"
          value={dateFilter}
          onChange={(e) => onDateChange(e.target.value)}
          className="w-full rounded-xl border border-gray-200 px-3 py-2.5 text-sm text-gray-700 focus:border-blue-400 focus:outline-none focus:ring-2 focus:ring-blue-500/40"
        />

        {/* Clear */}
        <button
          type="button"
          onClick={onClearFilters}
          className="flex w-full items-center justify-center gap-1.5 rounded-xl border border-gray-200 px-3 py-2.5 text-sm text-gray-600 transition-colors hover:bg-gray-50"
        >
          <X size={16} />
          Clear
        </button>
      </div>
    </div>
  );
}
