// src/components/DataTable.jsx
// Generic, reusable table shell used by Latest Bookings, Pending Verification,
// and Recent Reports. Accepts column defs + row renderer so each page can
// control its own cell content (badges, action buttons, etc.) while sharing
// consistent header, spacing, and responsive scroll behavior.

export default function DataTable({ columns, children, minWidth = '640px' }) {
  return (
    <div className="overflow-x-auto rounded-xl border border-surface-200">
      <table className="w-full text-left text-sm" style={{ minWidth }}>
        <thead>
          <tr className="border-b border-surface-200 bg-surface-50">
            {columns.map((col) => (
              <th
                key={col}
                className="whitespace-nowrap px-4 py-3 text-xs font-semibold uppercase tracking-wide text-ink-600/60"
              >
                {col}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-surface-200">{children}</tbody>
      </table>
    </div>
  )
}
