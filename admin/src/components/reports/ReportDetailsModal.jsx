import { useState, useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import toast from "react-hot-toast";
import {
  X,
  User,
  UserX,
  Tag,
  Calendar,
  AlertCircle,
  Link2,
  FileText,
  ClipboardCheck,
} from "lucide-react";
import { REPORT_STATUS, ADMIN_ACTIONS } from "../../data/reports";

function InfoRow({ icon: Icon, label, value }) {
  return (
    <div className="flex items-start gap-2.5">
      <Icon size={15} className="text-gray-400 mt-0.5 shrink-0" />
      <div>
        <p className="text-xs text-gray-400">{label}</p>
        <p className="text-sm text-gray-700">{value ?? "—"}</p>
      </div>
    </div>
  );
}

export default function ReportDetailsModal({ report, onClose, onSave }) {
  const [status, setStatus] = useState(report?.status ?? REPORT_STATUS.PENDING);
  const [adminNotes, setAdminNotes] = useState(report?.adminNotes ?? "");
  const [resolution, setResolution] = useState(report?.resolution ?? "");
  const [adminAction, setAdminAction] = useState(report?.adminAction ?? "No Action");

  // Reset local form state whenever a different report is opened.
  useEffect(() => {
    if (report) {
      setStatus(report.status ?? REPORT_STATUS.PENDING);
      setAdminNotes(report.adminNotes ?? "");
      setResolution(report.resolution ?? "");
      setAdminAction(report.adminAction ?? "No Action");
    }
  }, [report]);

  if (!report) return null;

  const handleSave = () => {
    // TODO: Replace with an API call to update the report record.
    onSave(report.id, { status, adminNotes, resolution, adminAction });
    toast.success(`Report ${report.id} updated successfully.`);
    onClose();
  };

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4"
        onClick={onClose}
      >
        <motion.div
          initial={{ opacity: 0, scale: 0.96, y: 10 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.96, y: 10 }}
          transition={{ duration: 0.18 }}
          onClick={(e) => e.stopPropagation()}
          className="bg-white rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        >
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 sticky top-0 bg-white rounded-t-2xl">
            <div>
              <h2 className="text-lg font-semibold text-gray-800">
                {report.subject ?? "Report Details"}
              </h2>
              <p className="text-xs text-gray-400">{report.id ?? "—"}</p>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors"
            >
              <X size={18} />
            </button>
          </div>

          <div className="px-6 py-5 space-y-6">
            {/* Report Information */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Report Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={Tag} label="Report Type" value={report.reportType} />
                <InfoRow icon={Calendar} label="Date Submitted" value={report.date} />
                <InfoRow icon={AlertCircle} label="Priority" value={report.priority} />
                <InfoRow
                  icon={Link2}
                  label="Related Booking"
                  value={report.relatedBooking ?? "Not linked to a booking"}
                />
              </div>
              {report.description && (
                <p className="mt-3 text-sm text-gray-600 bg-gray-50 rounded-xl p-3">
                  {report.description}
                </p>
              )}
            </section>

            {/* People Involved */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                People Involved
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={User} label="Reporter" value={report.reporter} />
                <InfoRow icon={UserX} label="Reported User" value={report.reportedUser} />
              </div>
            </section>

            {/* Admin Handling */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-1.5">
                <ClipboardCheck size={15} className="text-gray-400" />
                Admin Handling
              </h3>

              <div className="space-y-4">
                <div>
                  <label className="text-xs text-gray-400 mb-1 block">
                    Status
                  </label>
                  <select
                    value={status}
                    onChange={(e) => setStatus(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
                  >
                    {Object.values(REPORT_STATUS).map((opt) => (
                      <option key={opt} value={opt}>
                        {opt}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="text-xs text-gray-400 mb-1 block">
                    Admin Action
                  </label>
                  <select
                    value={adminAction}
                    onChange={(e) => setAdminAction(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
                  >
                    {ADMIN_ACTIONS.map((opt) => (
                      <option key={opt} value={opt}>
                        {opt}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="text-xs text-gray-400 mb-1 flex items-center gap-1.5">
                    <FileText size={13} />
                    Admin Notes
                  </label>
                  <textarea
                    value={adminNotes}
                    onChange={(e) => setAdminNotes(e.target.value)}
                    rows={3}
                    placeholder="Internal notes about this report..."
                    className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400 resize-none"
                  />
                </div>

                <div>
                  <label className="text-xs text-gray-400 mb-1 flex items-center gap-1.5">
                    <FileText size={13} />
                    Resolution
                  </label>
                  <textarea
                    value={resolution}
                    onChange={(e) => setResolution(e.target.value)}
                    rows={3}
                    placeholder="Describe the action taken to resolve this report..."
                    className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400 resize-none"
                  />
                </div>
              </div>
            </section>
          </div>

          {/* Footer actions */}
          <div className="flex justify-end gap-2 px-6 py-4 border-t border-gray-100 sticky bottom-0 bg-white rounded-b-2xl">
            <button
              type="button"
              onClick={onClose}
              className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50 transition-colors"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleSave}
              className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl bg-blue-600 text-sm text-white hover:bg-blue-700 transition-colors"
            >
              Save Changes
            </button>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
