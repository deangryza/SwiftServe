import { motion } from "framer-motion";
import { Eye, Calendar } from "lucide-react";
import { REPORT_STATUS } from "../../data/reports";

const STATUS_STYLES = {
  [REPORT_STATUS.PENDING]: "bg-amber-50 text-amber-600 border border-amber-200",
  [REPORT_STATUS.UNDER_REVIEW]:
    "bg-indigo-50 text-indigo-600 border border-indigo-200",
  [REPORT_STATUS.RESOLVED]: "bg-green-50 text-green-600 border border-green-200",
  [REPORT_STATUS.DISMISSED]: "bg-gray-100 text-gray-500 border border-gray-200",
};

const PRIORITY_STYLES = {
  Low: "bg-gray-50 text-gray-500 border border-gray-200",
  Medium: "bg-amber-50 text-amber-600 border border-amber-200",
  High: "bg-red-50 text-red-500 border border-red-200",
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

function PriorityBadge({ priority }) {
  const style =
    PRIORITY_STYLES[priority] || "bg-gray-50 text-gray-500 border border-gray-200";
  return (
    <span
      className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${style}`}
    >
      {priority || "—"}
    </span>
  );
}

export default function ReportTable({ reports, onViewDetails }) {
  if (!reports || reports.length === 0) {
    return (
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-10 text-center text-gray-400 text-sm">
        No reports match your current filters.
      </div>
    );
  }

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[1100px]">
          <thead>
            <tr className="bg-gray-50 text-gray-500 text-xs uppercase tracking-wide">
              <th className="text-left font-medium px-4 py-3">Report ID</th>
              <th className="text-left font-medium px-4 py-3">Subject</th>
              <th className="text-left font-medium px-4 py-3">Type</th>
              <th className="text-left font-medium px-4 py-3">Reporter</th>
              <th className="text-left font-medium px-4 py-3">Reported User</th>
              <th className="text-left font-medium px-4 py-3">Priority</th>
              <th className="text-left font-medium px-4 py-3">Date</th>
              <th className="text-left font-medium px-4 py-3">Status</th>
              <th className="text-right font-medium px-4 py-3">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {reports.map((r, idx) => (
              <motion.tr
                key={r?.id ?? idx}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.2, delay: idx * 0.02 }}
                className="hover:bg-gray-50/70 transition-colors"
              >
                <td className="px-4 py-3 font-medium text-gray-800">
                  {r?.id ?? "—"}
                </td>
                <td className="px-4 py-3 text-gray-700 max-w-[220px] truncate">
                  {r?.subject ?? "Untitled Report"}
                </td>
                <td className="px-4 py-3 text-gray-500">
                  {r?.reportType ?? "—"}
                </td>
                <td className="px-4 py-3 text-gray-700">
                  {r?.reporter ?? "—"}
                </td>
                <td className="px-4 py-3 text-gray-700">
                  {r?.reportedUser ?? "—"}
                </td>
                <td className="px-4 py-3">
                  <PriorityBadge priority={r?.priority} />
                </td>
                <td className="px-4 py-3 text-gray-500">
                  <span className="inline-flex items-center gap-1">
                    <Calendar size={13} className="text-gray-400" />
                    {r?.dateSubmitted ?? "—"}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <StatusBadge status={r?.status} />
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center justify-end">
                    <button
                      type="button"
                      onClick={() => onViewDetails(r)}
                      title="View Details"
                      className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-gray-500 hover:bg-blue-50 hover:text-blue-600 transition-colors text-xs font-medium"
                    >
                      <Eye size={14} />
                      View
                    </button>
                  </div>
                </td>
              </motion.tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
