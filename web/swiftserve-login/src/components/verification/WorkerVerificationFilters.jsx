import { Search, X } from "lucide-react";
import { VERIFICATION_STATUS } from "../../data/workerVerification";

export default function WorkerVerificationFilters({
  searchTerm,
  onSearchChange,
  statusFilter,
  onStatusChange,
  categoryFilter,
  onCategoryChange,
  categoryOptions,
  idFilter,
  onIdFilterChange,
  faceFilter,
  onFaceFilterChange,
  onClearFilters,
}) {
  const statusOptions = ["All", ...Object.values(VERIFICATION_STATUS)];

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 mb-6">
      <div className="flex flex-col lg:flex-row lg:items-center gap-3 flex-wrap">
        {/* Search */}
        <div className="relative flex-1 min-w-[220px]">
          <Search
            size={18}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"
          />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => onSearchChange(e.target.value)}
            placeholder="Search by worker ID, name, verification ID, or category..."
            className="w-full pl-10 pr-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
          />
        </div>

        {/* Status filter */}
        <select
          value={statusFilter}
          onChange={(e) => onStatusChange(e.target.value)}
          className="px-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
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
          className="px-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
        >
          <option value="All">All Categories</option>
          {categoryOptions.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>

        {/* ID verification filter */}
        <select
          value={idFilter}
          onChange={(e) => onIdFilterChange(e.target.value)}
          className="px-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
        >
          <option value="All">ID: All</option>
          <option value="Submitted">ID: Submitted</option>
          <option value="Not Submitted">ID: Not Submitted</option>
        </select>

        {/* Face verification filter */}
        <select
          value={faceFilter}
          onChange={(e) => onFaceFilterChange(e.target.value)}
          className="px-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
        >
          <option value="All">Face: All</option>
          <option value="Passed">Face: Passed</option>
          <option value="Not Verified">Face: Not Verified</option>
        </select>

        {/* Clear */}
        <button
          type="button"
          onClick={onClearFilters}
          className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50 transition-colors"
        >
          <X size={16} />
          Clear Filters
        </button>
      </div>
    </div>
  );
}
