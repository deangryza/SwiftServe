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
import { apiRequestBinary } from "../../lib/api";

// TODO(billing): local image links are backend routes needing the admin token,
// so they open via an authenticated fetch into a blob URL. GCS signed URLs
// keep plain anchors. Simplify to anchors only when VERIFICATION_STORAGE=gcs.
async function openProtectedDocument(url) {
  const path = url.startsWith("http") ? new URL(url).pathname : url;
  const blob = await apiRequestBinary(path);
  window.open(URL.createObjectURL(blob), "_blank", "noopener");
}

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
  const [saving, setSaving] = useState(false);
  const [openingDocument, setOpeningDocument] = useState(false);

  useEffect(() => {
    if (request) {
      setAdminNotes(request.adminNotes ?? "");
    }
  }, [request]);

  if (!request) return null;

  const today = new Date().toISOString().slice(0, 10);

  const applyAction = async (nextStatus, toastMessage) => {
    setSaving(true);
    try {
      await onUpdate(request.verificationId, { status: nextStatus, adminNotes });
      toast.success(toastMessage);
      onClose();
    } catch (error) {
      toast.error(error.message || "Unable to update verification.");
    } finally {
      setSaving(false);
    }
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

  const handleOpenDocument = async (url) => {
    if (request.storageBackend !== "local") return;
    setOpeningDocument(true);
    try {
      await openProtectedDocument(url);
    } catch (error) {
      toast.error(error.message || "Unable to open the document.");
    } finally {
      setOpeningDocument(false);
    }
  };

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-0 sm:p-4"
        onClick={onClose}
      >
        <motion.div
          initial={{ opacity: 0, scale: 0.96, y: 10 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          exit={{ opacity: 0, scale: 0.96, y: 10 }}
          transition={{ duration: 0.18 }}
          onClick={(e) => e.stopPropagation()}
          className="h-full w-full max-w-2xl overflow-y-auto bg-white shadow-xl sm:h-auto sm:max-h-[90vh] sm:rounded-2xl"
        >
          {/* Header */}
          <div className="sticky top-0 flex items-center justify-between border-b border-gray-100 bg-white px-4 py-4 sm:rounded-t-2xl sm:px-6">
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

          <div className="space-y-6 px-4 py-5 sm:px-6">
            {/* TODO(face-verification): temporary ID-only banner. Remove once
                automatic face matching is re-enabled. */}
            {request.faceVerificationProvider === "bypassed" && (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                Face check bypassed — review the government ID manually before
                approving.
              </div>
            )}
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

            {(request.governmentIdUrl || request.facePhotoUrl) && (
              <section>
                <h3 className="text-sm font-semibold text-gray-700 mb-3">Submitted Documents</h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  {request.governmentIdUrl && request.storageBackend === "local" ? (
                    <button
                      type="button"
                      onClick={() => handleOpenDocument(request.governmentIdUrl)}
                      disabled={openingDocument}
                      className="text-sm text-blue-600 underline text-left disabled:opacity-50"
                    >
                      {openingDocument ? "Opening…" : "Open government ID"}
                    </button>
                  ) : (
                    request.governmentIdUrl && <a href={request.governmentIdUrl} target="_blank" rel="noreferrer" className="text-sm text-blue-600 underline">Open government ID</a>
                  )}
                  {request.facePhotoUrl && <a href={request.facePhotoUrl} target="_blank" rel="noreferrer" className="text-sm text-blue-600 underline">Open face photo</a>}
                </div>
              </section>
            )}

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
                  value={
                    request.faceVerificationProvider === "bypassed"
                      ? "Bypassed — manual review"
                      : request.faceVerified
                        ? "Passed"
                        : "Not Verified"
                  }
                />
                <InfoRow
                  icon={ScanFace}
                  label="Match Confidence"
                  value={request.faceMatchConfidence == null
                    ? "—"
                    : `${Number(request.faceMatchConfidence).toFixed(2)}%`}
                />
                <InfoRow
                  icon={ClipboardCheck}
                  label="Match Threshold"
                  value={request.faceMatchThreshold == null
                    ? "—"
                    : `${Number(request.faceMatchThreshold).toFixed(0)}%`}
                />
                <InfoRow
                  icon={ClipboardCheck}
                  label="Provider"
                  value={request.faceVerificationProvider ?? "—"}
                />
                <InfoRow
                  icon={Calendar}
                  label="Face Check Time"
                  value={request.faceVerifiedAt ?? "—"}
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
          <div className="sticky bottom-0 flex flex-col gap-2 border-t border-gray-100 bg-white px-4 py-4 sm:flex-row sm:justify-end sm:rounded-b-2xl sm:px-6">
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
              disabled={saving}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl border border-orange-200 text-sm text-orange-600 hover:bg-orange-50 transition-colors"
            >
              <RotateCcw size={15} />
              Request Resubmission
            </button>
            <button
              type="button"
              onClick={handleReject}
              disabled={saving}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-red-600 text-sm text-white hover:bg-red-700 transition-colors"
            >
              <XCircle size={15} />
              Reject
            </button>
            <button
              type="button"
              onClick={handleVerify}
              disabled={saving}
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
