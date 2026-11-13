import { useState, useEffect, useCallback } from "react";
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
import { protectedImagePath, usesProtectedImages } from '../../lib/verificationImages';
import { useAdminAccess } from '../../lib/AdminAccessContext';
import { canApproveEvidence, canReviewEvidence, reviewBlockedReason, verificationRows, verificationBlockers } from '../../lib/verificationEvidence';

// TODO(billing): local image links are backend routes needing the admin token,
// so they load via an authenticated fetch into a blob URL. GCS signed URLs are
// used as-is. Simplify when VERIFICATION_STORAGE=gcs.
async function loadImage(url, backend) {
  if (!url) return null;
  if (!usesProtectedImages(backend)) return url;
  return URL.createObjectURL(await apiRequestBinary(protectedImagePath(url)));
}

// Photos live on the disk of the backend that received the upload, so a
// different backend (or a removed file) answers 404.
const imageError = (error) => /\(404\)/.test(error?.message || "")
  ? "Not stored on the server this dashboard is connected to."
  : error?.message || "Could not load this photo.";

function PhotoPanel({ label, photo }) {
  return (
    <figure className="flex min-w-0 flex-col">
      <figcaption className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">{label}</figcaption>
      <div className="flex h-72 items-center justify-center overflow-hidden rounded-xl bg-gray-900/5 sm:h-[26rem]">
        {photo?.src ? (
          <a href={photo.src} target="_blank" rel="noreferrer" title="Open full size" className="flex h-full w-full items-center justify-center">
            <img src={photo.src} alt={label} className="max-h-full max-w-full object-contain" />
          </a>
        ) : (
          <p className="px-4 text-center text-sm text-gray-500">{photo?.error || (photo === undefined ? "Loading…" : "No photo submitted.")}</p>
        )}
      </div>
    </figure>
  );
}

function PhotoCompare({ request, onClose }) {
  const [photos, setPhotos] = useState({ id: undefined, face: undefined });

  useEffect(() => {
    let cancelled = false;
    const created = [];
    const load = (key, url) => loadImage(url, request.storageBackend)
      .then((src) => {
        if (src?.startsWith("blob:")) created.push(src);
        if (!cancelled) setPhotos((prev) => ({ ...prev, [key]: src ? { src } : null }));
      })
      .catch((error) => { if (!cancelled) setPhotos((prev) => ({ ...prev, [key]: { error: imageError(error) } })); });
    load("id", request.governmentIdUrl);
    load("face", request.facePhotoUrl);
    const onKey = (e) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKey);
    return () => {
      cancelled = true;
      created.forEach((src) => URL.revokeObjectURL(src));
      document.removeEventListener("keydown", onKey);
    };
  }, [request, onClose]);

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-2 sm:p-6" onClick={(e) => { e.stopPropagation(); onClose(); }}>
      <div role="dialog" aria-modal="true" aria-label="Compare ID and face photo" onClick={(e) => e.stopPropagation()}
        className="max-h-full w-full max-w-5xl overflow-y-auto rounded-2xl bg-white shadow-xl">
        <div className="flex items-start justify-between gap-3 border-b border-gray-100 px-4 py-3 sm:px-6">
          <div className="min-w-0">
            <p className="truncate font-semibold text-gray-800">{request.workerName} · ID and face</p>
            <p className="text-xs text-gray-500">
              {request.idType || "ID"} · Face match {formatPercent(request.faceMatchConfidence, 1)}
              {request.faceMatchBand ? ` · ${BAND_LABELS[request.faceMatchBand] || request.faceMatchBand}` : ""}
            </p>
          </div>
          <button type="button" aria-label="Close comparison" onClick={onClose} className="rounded-lg p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600">
            <X size={18} />
          </button>
        </div>
        <div className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2 sm:p-6">
          <PhotoPanel label="Government ID" photo={photos.id} />
          <PhotoPanel label="Selfie" photo={photos.face} />
        </div>
        <p className="px-4 pb-4 text-xs text-gray-400 sm:px-6">Check that the face, name and photo on the ID belong to the same person. Click a photo to open it full size.</p>
      </div>
    </div>
  );
}

const BAND_LABELS = {
  strong: "Strong match",
  borderline: "Borderline — review photos",
  mismatch: "No match",
};

// Older records stored the threshold as a 0-1 distance; newer ones store a
// 0-100 similarity.
function formatPercent(value, digits = 0) {
  if (value == null) return "—";
  const number = Number(value);
  return `${(number <= 1 ? number * 100 : number).toFixed(digits)}%`;
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
  const { can } = useAdminAccess();
  const [adminNotes, setAdminNotes] = useState(request?.adminNotes ?? "");
  const [saving, setSaving] = useState(false);
  const [comparing, setComparing] = useState(false);

  useEffect(() => {
    if (request) {
      setAdminNotes(request.adminNotes ?? "");
    }
  }, [request]);

  if (!request) return null;
  const canManage = can('verification.manage');
  const reviewable = canReviewEvidence(request, canManage);
  const approvalReady = canApproveEvidence(request, canManage);
  const blockedReason = reviewBlockedReason(request, canManage);

  const today = new Date().toISOString().slice(0, 10);

  const applyAction = async (nextStatus, toastMessage) => {
    if (!reviewable || (nextStatus === VERIFICATION_STATUS.VERIFIED && !approvalReady)) return;
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
    applyAction(VERIFICATION_STATUS.VERIFIED, "Verification approved.");

  const handleReject = () =>
    applyAction(VERIFICATION_STATUS.REJECTED, "Verification rejected.");

  const handleResubmission = () =>
    applyAction(
      VERIFICATION_STATUS.RESUBMISSION_REQUIRED,
      "Resubmission requested."
    );

  const closeCompare = useCallback(() => setComparing(false), []);

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
                {request.workerName ?? "User Verification"}
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
            {request.autoVerified && (
              <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
                Legacy face-match approval ({formatPercent(request.faceMatchConfidence, 1)}). This is not official PSA authentication.
                This historical record is retained; reopening it requires a separately approved transition.
              </div>
            )}
            {request.faceReviewFlag === "borderline" && (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                Borderline face match requires further evidence or recapture. Government authentication and trusted liveness remain mandatory.
              </div>
            )}
            {request.faceVerificationProvider === "bypassed" && (
              <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                Submitted without a face check — review the government ID manually
                before approving.
              </div>
            )}
            {/* User Information */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                User Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={User} label="User ID" value={request.workerId} />
                <InfoRow icon={User} label="User Type" value={request.userType} />
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
                <button
                  type="button"
                  onClick={() => setComparing(true)}
                  className="flex w-full items-center gap-3 rounded-xl border border-gray-200 p-3 text-left hover:border-blue-300 hover:bg-blue-50/40"
                >
                  <span className="flex shrink-0 -space-x-2">
                    <span className="flex size-9 items-center justify-center rounded-lg bg-blue-50 text-blue-600 ring-2 ring-white"><IdCard size={16} /></span>
                    <span className="flex size-9 items-center justify-center rounded-lg bg-indigo-50 text-indigo-600 ring-2 ring-white"><ScanFace size={16} /></span>
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-medium text-gray-800">Compare ID and face</span>
                    <span className="block text-xs text-gray-500">View the government ID and selfie side by side</span>
                  </span>
                </button>
                {comparing && <PhotoCompare request={request} onClose={closeCompare} />}
              </section>
            )}

            {/* Verification Information */}
            <section>
              <div className="mb-5 rounded-xl border border-amber-200 bg-amber-50 p-4" aria-label="Separate verification checks">
                <h3 className="font-semibold text-gray-900">Independent verification checks</h3>
                <dl className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
                  {verificationRows(request).map(([label, value]) => <div key={label}><dt className="text-sm text-gray-600">{label}</dt><dd className="break-words text-sm font-semibold text-gray-900">{value}</dd></div>)}
                </dl>
                <ul className="mt-4 list-disc space-y-1 pl-5 text-sm text-gray-700">{verificationBlockers(request).map((reason, index) => <li key={index}>{reason}</li>)}</ul>
                {!approvalReady && <p className="mt-3 text-sm font-medium">Approval is unavailable until all mandatory backend checks pass. Legacy records remain protected.</p>}
              </div>
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
                  label="Face Comparison"
                  value={
                    request.faceVerificationProvider === "bypassed"
                      ? "Bypassed — manual review"
                      : request.faceVerified
                        ? BAND_LABELS[request.faceMatchBand] ?? "Passed"
                        : "Not Verified"
                  }
                />
                <InfoRow
                  icon={ScanFace}
                  label="Face Similarity"
                  value={formatPercent(request.faceMatchConfidence, 2)}
                />
                <InfoRow
                  icon={ClipboardCheck}
                  label="Thresholds"
                  value={request.faceAutoVerifyMin == null
                    ? `Review ≥ ${formatPercent(request.faceMatchThreshold)}`
                    : `Strong face band ≥ ${formatPercent(request.faceAutoVerifyMin)} · Review band ≥ ${formatPercent(request.faceMatchThreshold)}`}
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
                  disabled={!reviewable || saving}
                  onChange={(e) => setAdminNotes(e.target.value)}
                  rows={3}
                  placeholder="Add notes about this verification review..."
                  className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400 resize-none"
                />
              </div>
              {blockedReason && (
                <p role="status" className="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
                  {blockedReason}
                </p>
              )}
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
              disabled={saving || !reviewable}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl border border-orange-200 text-sm text-orange-600 hover:bg-orange-50 disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
            >
              <RotateCcw size={15} />
              Request Resubmission
            </button>
            <button
              type="button"
              onClick={handleReject}
              disabled={saving || !reviewable}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-red-600 text-sm text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50 transition-colors"
            >
              <XCircle size={15} />
              Reject
            </button>
            <button
              type="button"
              onClick={handleVerify}
              disabled={saving || !approvalReady}
              className="inline-flex items-center justify-center gap-1.5 px-3 py-2 rounded-xl bg-amber-300 text-sm text-gray-900 hover:bg-amber-400 disabled:opacity-50 transition-colors"
            >
              <CheckCircle2 size={15} />
              Verify User
            </button>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
