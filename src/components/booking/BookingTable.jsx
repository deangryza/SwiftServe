import { motion } from "framer-motion";
import { Eye, Ban, ShieldAlert, MapPin, Calendar, Clock } from "lucide-react";
import { STATUS } from "../../data/bookings";

const STATUS_STYLES = {
  [STATUS.PENDING]: "bg-amber-50 text-amber-600 border border-amber-200",
  [STATUS.ACCEPTED]: "bg-blue-50 text-blue-600 border border-blue-200",
  [STATUS.IN_PROGRESS]:
    "bg-indigo-50 text-indigo-600 border border-indigo-200",
  [STATUS.COMPLETED]: "bg-green-50 text-green-600 border border-green-200",
  [STATUS.CANCELLED]: "bg-red-50 text-red-500 border border-red-200",
};

function StatusBadge({ status }) {
  const style =
    STATUS_STYLES[status] || "bg-gray-50 text-gray-500 border border-gray-200";
  return (
    <span
      className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${style}`}
    >
      {status || "Unknown"}
    </span>
  );
}

// Business rule: bookings are only freely cancellable while Pending.
// Accepted / In Progress require an admin override (dispute handling).
// Completed / Cancelled bookings cannot be cancelled at all.
function getCancelMode(status) {
  if (status === STATUS.PENDING) return "direct";
  if (status === STATUS.ACCEPTED || status === STATUS.IN_PROGRESS)
    return "override";
  return "none";
}

export default function BookingTable({ bookings, onViewDetails, onCancel }) {
  if (!bookings || bookings.length === 0) {
    return (
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-10 text-center text-gray-400 text-sm">
        No bookings match your current filters.
      </div>
    );
  }

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[1100px]">
          <thead>
            <tr className="bg-gray-50 text-gray-500 text-xs uppercase tracking-wide">
              <th className="text-left font-medium px-4 py-3">Booking ID</th>
              <th className="text-left font-medium px-4 py-3">
                Service / Task
              </th>
              <th className="text-left font-medium px-4 py-3">Client</th>
              <th className="text-left font-medium px-4 py-3">Provider</th>
              <th className="text-left font-medium px-4 py-3">Category</th>
              <th className="text-left font-medium px-4 py-3">Date</th>
              <th className="text-left font-medium px-4 py-3">Time</th>
              <th className="text-left font-medium px-4 py-3">Location</th>
              <th className="text-left font-medium px-4 py-3">Status</th>
              <th className="text-right font-medium px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {bookings.map((b, idx) => {
              const cancelMode = getCancelMode(b?.status);
              return (
                <motion.tr
                  key={b?.id ?? idx}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 0.2, delay: idx * 0.02 }}
                  className="hover:bg-gray-50/70 transition-colors"
                >
                  <td className="px-4 py-3 font-medium text-gray-800">
                    {b?.id ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    {b?.serviceTitle ?? "Untitled Service"}
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    {b?.clientName ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    {b?.providerName ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {b?.category ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    <span className="inline-flex items-center gap-1">
                      <Calendar size={13} className="text-gray-400" />
                      {b?.date ?? "—"}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    <span className="inline-flex items-center gap-1">
                      <Clock size={13} className="text-gray-400" />
                      {b?.time ?? "—"}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    <span className="inline-flex items-center gap-1">
                      <MapPin size={13} className="text-gray-400" />
                      {b?.location ?? "—"}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={b?.status} />
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-2">
                      <button
                        type="button"
                        onClick={() => onViewDetails(b)}
                        title="View Details"
                        className="p-2 rounded-lg text-gray-500 hover:bg-blue-50 hover:text-blue-600 transition-colors"
                      >
                        <Eye size={16} />
                      </button>

                      {cancelMode === "direct" && (
                        <button
                          type="button"
                          onClick={() => onCancel(b, "direct")}
                          title="Cancel Booking"
                          className="p-2 rounded-lg text-gray-500 hover:bg-red-50 hover:text-red-600 transition-colors"
                        >
                          <Ban size={16} />
                        </button>
                      )}

                      {cancelMode === "override" && (
                        <button
                          type="button"
                          onClick={() => onCancel(b, "override")}
                          title="Cancel (Admin Override — Dispute)"
                          className="p-2 rounded-lg text-gray-500 hover:bg-amber-50 hover:text-amber-600 transition-colors"
                        >
                          <ShieldAlert size={16} />
                        </button>
                      )}
                    </div>
                  </td>
                </motion.tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
