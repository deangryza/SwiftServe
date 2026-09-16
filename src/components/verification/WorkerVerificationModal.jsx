import { useState, useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import toast from "react-hot-toast";
import {
  X,
  User,
  Mail,
  Phone,
  MapPin,
  Tag,
  Calendar,
  IdCard,
  ScanFace,
  ClipboardCheck,
  CheckCircle2,
  XCircle,
  RotateCcw,
} from "lucide-react";
import { VERIFICATION_STATUS } from "../../data/workerVerification";

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

export default function WorkerVerificationModal({ request, onClose, onUpdate }) {
  const [adminNotes, setAdminNotes] = useState(request?.adminNotes ?? "");

  useEffect(() => {
    if (request) {
      setAdminNotes(request.adminNotes ?? "");
    }
  }, [request]);

  if (!request) return null;

  const today = new Date().toISOString().slice(0, 10);

  const applyAction = (nextStatus, toastMessage) => {
    // TODO: Replace with an API call to update the verification record.
    onUpdate(request.verificationId, {
      status: nextStatus,
      adminNotes,
      reviewDate: today,
      reviewedBy: "Admin",
    });
    toast.success(toastMessage);
    onClose();
  };

  const handleVerify = () =>
    applyAction(VERIFICATION_STATUS.VERIFIED, "Worker verification approved.");

  const handleReject = () =>
    applyAction(VERIFICATION_STATUS.REJECTED, "Worker verification rejected.");

  const handleResubmission = () =>
    applyAction(
      VERIFICATION_STATUS.RESUBMISSION_REQUIRED,
      "Worker resubmission requested."
    );

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
                {request.workerName ?? "Worker Verification"}
              </h2>
              <p className="text-xs text-gray-400">{request.verificationId ?? "—"}</p>
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
            {/* Worker Information */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Worker Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={User} label="Worker ID" value={request.workerId} />
                <InfoRow icon={Tag} label="Category" value={request.category} />
                <InfoRow icon={MapPin} label="Location" value={request.location} />
                <InfoRow icon={Calendar} label="Date Joined" value={request.dateJoined} />
                <InfoRow icon={Mail} label="Email" value={request.email} />
                <InfoRow icon={Phone} label="Phone" value={request.phone} />
              </div>
            </section>

            {/* Verification Information */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Verification Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow
                  icon={Calendar}
                  label="Submission Date"
                  value={request.submittedDate}
                />
                <InfoRow icon={ClipboardCheck} label="Current Status" value={request.status} />
                <InfoRow icon={IdCard} label="ID Type" value={request.idType} />
                <InfoRow
                  icon={IdCard}
                  label="ID Number"
                  value={request.maskedIdNumber}
                />
                <InfoRow
                  icon={IdCard}
                  label="ID Submission"
                  value={request.idSubmitted ? "Submitted" : "Not Submitted"}
                />
                <InfoRow
                  icon={ScanFace}
                  label="Face Verification"
                  value={request.faceVerified ? "Passed" : "Not Verified"}
                />
              </div>
            </section>

            {/* Review Information */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Review Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4">
                <InfoRow
                  icon={Calendar}
                  label="Review Date"
                  value={request.reviewDate ?? "Not yet reviewed"}
                />
                <InfoRow
                  icon={User}
                  label="Reviewed By"
                  value={request.reviewedBy ?? "—"}
                />
              </div>

              <div>
                <label className="text-xs text-gray-400 mb-1 block">
                  Admin Notes
                </label>
                <textarea
                  value={adminNotes}
                  onChange={(e) => setAdminNotes(e.target.value)}
                  rows={3}
                  placeholder="Add notes about this verification review..."
                  className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400 resize-none"
                />
              </div>
            </section>
          </div>

          {/* Footer actions */}
          <div className="flex flex-col sm:flex-row sm:justify-end gap-2 px-6 py-4 border-t border-gray-100 sticky bottom-0 bg-white rounded-b-2xl">
            <button
              type="button"
              onClick={onClose}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50 transition-colors order-last sm:order-first"
            >
              Close
            </button>
            <button
              type="button"
              onClick={handleResubmission}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl border border-orange-200 text-sm text-orange-600 hover:bg-orange-50 transition-colors"
            >
              <RotateCcw size={15} />
              Request Resubmission
            </button>
            <button
              type="button"
              onClick={handleReject}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-red-600 text-sm text-white hover:bg-red-700 transition-colors"
            >
              <XCircle size={15} />
              Reject
            </button>
            <button
              type="button"
              onClick={handleVerify}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-green-600 text-sm text-white hover:bg-green-700 transition-colors"
            >
              <CheckCircle2 size={15} />
              Verify Worker
            </button>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
