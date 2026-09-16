// Destination: src/components/users/UserDetailsModal.jsx
import { AnimatePresence, motion } from "framer-motion";
import {
  X,
  Mail,
  Phone,
  MapPin,
  BadgeCheck,
  ScanFace,
  Star,
  Briefcase,
  Calendar,
} from "lucide-react";
import StatusBadge from "./StatusBadge";

export default function UserDetailsModal({ user, onClose }) {
  return (
    <AnimatePresence>
      {user && (
        <motion.div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
        >
          <motion.div
            className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white shadow-xl"
            initial={{ opacity: 0, y: 24, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 24, scale: 0.98 }}
            transition={{ duration: 0.2 }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="flex items-start justify-between border-b border-gray-100 p-5">
              <div className="flex items-center gap-4">
                <img
                  src={user.profilePic}
                  alt={user.fullName}
                  className="h-16 w-16 rounded-full object-cover ring-2 ring-blue-100"
                />
                <div>
                  <h2 className="text-lg font-semibold text-gray-900">
                    {user.fullName}
                  </h2>
                  <p className="text-sm text-gray-500">
                    {user.role} &middot; {user.id}
                  </p>
                  <div className="mt-1">
                    <StatusBadge status={user.status} />
                  </div>
                </div>
              </div>
              <button
                onClick={onClose}
                className="rounded-full p-1.5 text-gray-400 transition hover:bg-gray-100 hover:text-gray-600"
                aria-label="Close"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            {/* Body */}
            <div className="grid grid-cols-1 gap-5 p-5 sm:grid-cols-2">
              <InfoRow icon={Mail} label="Email" value={user.email} />
              <InfoRow icon={Phone} label="Phone Number" value={user.phone} />
              <InfoRow label="Age" value={String(user.age)} />
              <InfoRow label="Gender" value={user.gender} />
              <InfoRow
                icon={MapPin}
                label="Address"
                value={user.address}
                span
              />
              <InfoRow
                icon={Calendar}
                label="Registration Date"
                value={user.registrationDate}
              />

              {user.role === "Worker" && (
                <>
                  <InfoRow
                    icon={Briefcase}
                    label="Completed Jobs"
                    value={String(user.completedJobs)}
                  />
                  <InfoRow
                    icon={Star}
                    label="Average Rating"
                    value={
                      user.averageRating > 0
                        ? `${user.averageRating.toFixed(1)} / 5.0`
                        : "No ratings yet"
                    }
                  />
                  <InfoRow
                    label="Skills"
                    value={user.skills.length ? user.skills.join(", ") : "None listed"}
                    span
                  />
                </>
              )}
            </div>

            {/* Verification section */}
            <div className="border-t border-gray-100 p-5">
              <h3 className="mb-3 text-sm font-semibold text-gray-800">
                Identity Verification
              </h3>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                <VerificationTile
                  icon={BadgeCheck}
                  label="Submitted ID"
                  value={user.submittedId}
                  tone="neutral"
                />
                <VerificationTile
                  icon={ScanFace}
                  label="Facial Verification"
                  value={user.faceVerified ? "YES" : "NO"}
                  tone={user.faceVerified ? "good" : "bad"}
                />
                <VerificationTile
                  icon={BadgeCheck}
                  label="AI Verification"
                  value={user.aiVerification}
                  tone={user.aiVerification === "MATCHED" ? "good" : "bad"}
                />
              </div>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function InfoRow({ icon: Icon, label, value, span }) {
  return (
    <div className={span ? "sm:col-span-2" : ""}>
      <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
        {label}
      </p>
      <div className="mt-1 flex items-center gap-1.5 text-sm text-gray-800">
        {Icon && <Icon className="h-4 w-4 text-gray-400" />}
        <span>{value}</span>
      </div>
    </div>
  );
}

function VerificationTile({ icon: Icon, label, value, tone }) {
  const toneStyles = {
    good: "bg-green-50 text-green-700 ring-green-600/20",
    bad: "bg-red-50 text-red-700 ring-red-600/20",
    neutral: "bg-gray-50 text-gray-700 ring-gray-500/20",
  };

  return (
    <div
      className={`rounded-lg p-3 ring-1 ${toneStyles[tone]} flex flex-col gap-1`}
    >
      <div className="flex items-center gap-1.5 text-xs font-medium">
        <Icon className="h-3.5 w-3.5" />
        {label}
      </div>
      <p className="text-sm font-semibold">{value}</p>
    </div>
  );
}
