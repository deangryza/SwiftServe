import { motion } from "framer-motion";
import { Eye, Calendar, CheckCircle2, XCircle } from "lucide-react";
import { formatVerificationStatus, VERIFICATION_STATUS } from "../../data/workerVerification";

const STATUS_STYLES = {
  [VERIFICATION_STATUS.PENDING]: "bg-amber-50 text-amber-600 border border-amber-200",
  [VERIFICATION_STATUS.UNDER_REVIEW]:
    "bg-indigo-50 text-indigo-600 border border-indigo-200",
  [VERIFICATION_STATUS.VERIFIED]: "bg-green-50 text-green-600 border border-green-200",
  [VERIFICATION_STATUS.REJECTED]: "bg-red-50 text-red-500 border border-red-200",
  [VERIFICATION_STATUS.RESUBMISSION_REQUIRED]:
    "bg-orange-50 text-orange-600 border border-orange-200",
};

function StatusBadge({ status }) {
  const style =
    STATUS_STYLES[status] || "bg-gray-50 text-gray-500 border border-gray-200";
  return (
    <span
      className={`inline-flex max-w-full items-center px-2.5 py-1 rounded-full text-xs font-medium leading-tight ${style}`}
      title={formatVerificationStatus(status)}
    >
      {status === VERIFICATION_STATUS.VERIFIED ? "Access recorded" : formatVerificationStatus(status)}
    </span>
  );
}

function BooleanBadge({ value, trueLabel, falseLabel }) {
  return value ? (
    <span className="inline-flex items-center gap-1 text-xs font-medium text-green-600">
      <CheckCircle2 size={13} />
      {trueLabel}
    </span>
  ) : (
    <span className="inline-flex items-center gap-1 text-xs font-medium text-gray-400">
      <XCircle size={13} />
      {falseLabel}
    </span>
  );
}

// Submitted dates arrive as ISO strings; show a short local date instead.
function formatDate(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return value ?? "—";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

export default function WorkerVerificationTable({ requests, onViewDetails }) {
  if (!requests || requests.length === 0) {
    return (
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-10 text-center text-gray-400 text-sm">
        No verification requests match your current filters.
      </div>
    );
  }

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full table-fixed text-sm min-w-[900px]">
          <thead>
            <tr className="bg-gray-50 text-gray-500 text-xs uppercase tracking-wide">
              <th className="w-[11%] text-left font-medium px-4 py-3">Verification ID</th>
              <th className="w-[14%] text-left font-medium px-4 py-3">User</th>
              <th className="w-[10%] text-left font-medium px-4 py-3">Category</th>
              <th className="w-[12%] text-left font-medium px-4 py-3">Location</th>
              <th className="w-[11%] text-left font-medium px-4 py-3">Submitted</th>
              <th className="w-[9%] text-center font-medium px-4 py-3">ID Status</th>
              <th className="w-[9%] text-center font-medium px-4 py-3">Face Status</th>
              <th className="w-[16%] text-center font-medium px-4 py-3">Status</th>
              <th className="w-[8%] text-right font-medium px-4 py-3">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {requests.map((r, idx) => (
              <motion.tr
                key={r?.verificationId ?? idx}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.2, delay: idx * 0.02 }}
                className="hover:bg-gray-50/70 transition-colors"
              >
                <td className="truncate px-4 py-3 font-medium text-gray-800" title={r?.verificationId}>
                  {r?.verificationId ?? "—"}
                </td>
                <td className="px-4 py-3 text-gray-700" title={r?.workerName}>
                  <div className="truncate">{r?.workerName ?? "—"}</div>
                  {r?.userType && (
                    <span
                      className={`mt-1 inline-flex rounded-full px-2 py-0.5 text-[11px] font-medium ${
                        r.userType === "Client" ? "bg-sky-50 text-sky-700" : "bg-amber-50 text-amber-700"
                      }`}
                    >
                      {r.userType}
                    </span>
                  )}
                </td>
                <td className="truncate px-4 py-3 text-gray-500" title={r?.category}>
                  {r?.category ?? "—"}
                </td>
                <td className="truncate px-4 py-3 text-gray-500" title={r?.location}>
                  {r?.location ?? "—"}
                </td>
                <td className="truncate px-4 py-3 text-gray-500" title={r?.submittedDate}>
                  <Calendar size={13} className="mr-1 inline align-[-2px] text-gray-400" />
                  {formatDate(r?.submittedDate)}
                </td>
                <td className="px-4 py-3 text-center">
                  <BooleanBadge
                    value={r?.idSubmitted}
                    trueLabel="Submitted"
                    falseLabel="Not Submitted"
                  />
                </td>
                <td className="px-4 py-3 text-center">
                  <BooleanBadge
                    value={r?.faceVerified}
                    trueLabel="Passed"
                    falseLabel="Not Verified"
                  />
                </td>
                <td className="px-2 py-3 text-center">
                  <StatusBadge status={r?.status} />
                  {r?.autoVerified && (
                    <span
                      className="m-1 inline-flex items-center rounded-full border border-blue-200 bg-blue-50 px-2 py-0.5 text-xs font-medium text-blue-700"
                      title="Verified automatically on a strong face match, without an administrator"
                    >
                      Auto
                    </span>
                  )}
                </td>
                <td className="px-2 py-3">
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
