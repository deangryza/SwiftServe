import { AnimatePresence, motion } from "framer-motion";
import {
  X,
  MapPin,
  BadgeCheck,
  ScanFace,
  Star,
  Briefcase,
  Calendar,
  User,
} from "lucide-react";
import StatusBadge from "./StatusBadge";

export default function UserDetailsModal({ user, onClose }) {
  if (!user) return null;

  const isWorker = user.id?.startsWith("WRK-");
  const role = isWorker ? "Worker" : "Client";

  return (
    <AnimatePresence>
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
              {/* Profile placeholder using first letter */}
              <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-blue-100 text-xl font-semibold text-blue-600 ring-2 ring-blue-100">
                {user.name?.charAt(0)?.toUpperCase() || "U"}
              </div>

              <div>
                <h2 className="text-lg font-semibold text-gray-900">
                  {user.name || "Unknown User"}
                </h2>

                <p className="text-sm text-gray-500">
                  {role} &middot; {user.id}
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

          {/* Basic Information */}
          <div className="grid grid-cols-1 gap-5 p-5 sm:grid-cols-2">
            <InfoRow
              icon={User}
              label="Full Name"
              value={user.name || "—"}
            />

            <InfoRow
              label="Role"
              value={role}
            />

            <InfoRow
              icon={MapPin}
              label="Location"
              value={user.location || "—"}
            />

            <InfoRow
              icon={Calendar}
              label="Registration Date"
              value={user.joinDate || "—"}
            />

            {isWorker && (
              <>
                <InfoRow
                  icon={Briefcase}
                  label="Service Category"
                  value={user.category || "—"}
                />

                <InfoRow
                  icon={Briefcase}
                  label="Completed Jobs"
                  value={String(user.jobsCompleted ?? 0)}
                />

                <InfoRow
                  icon={Star}
                  label="Average Rating"
                  value={
                    user.rating
                      ? `${user.rating} / 5.0`
                      : "No ratings yet"
                  }
                />
              </>
            )}

            {!isWorker && (
              <InfoRow
                label="Bookings Made"
                value={String(user.bookingsMade ?? 0)}
              />
            )}
          </div>

          {/* Verification Section */}
          <div className="border-t border-gray-100 p-5">
            <h3 className="mb-3 text-sm font-semibold text-gray-800">
              Identity Verification
            </h3>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <VerificationTile
                icon={BadgeCheck}
                label="ID Submitted"
                value={user.idSubmitted ? "YES" : "NO"}
                tone={user.idSubmitted ? "good" : "bad"}
              />

              <VerificationTile
                icon={ScanFace}
                label="Facial Verification"
                value={user.faceVerified ? "VERIFIED" : "NOT VERIFIED"}
                tone={user.faceVerified ? "good" : "bad"}
              />
            </div>
          </div>

          {/* Worker Information */}
          {isWorker && (
            <div className="border-t border-gray-100 p-5">
              <h3 className="mb-3 text-sm font-semibold text-gray-800">
                Worker Information
              </h3>

              <div className="rounded-xl bg-gray-50 p-4">
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                      Service Category
                    </p>
                    <p className="mt-1 text-sm font-medium text-gray-800">
                      {user.category || "—"}
                    </p>
                  </div>

                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                      Location
                    </p>
                    <p className="mt-1 text-sm font-medium text-gray-800">
                      {user.location || "—"}
                    </p>
                  </div>

                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                      Completed Jobs
                    </p>
                    <p className="mt-1 text-sm font-medium text-gray-800">
                      {user.jobsCompleted ?? 0}
                    </p>
                  </div>

                  <div>
                    <p className="text-xs font-medium uppercase tracking-wide text-gray-400">
                      Rating
                    </p>
                    <p className="mt-1 text-sm font-medium text-gray-800">
                      {user.rating || "No ratings yet"}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          )}
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

function InfoRow({ icon: Icon, label, value }) {
  return (
    <div>
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
      className={`flex flex-col gap-1 rounded-lg p-3 ring-1 ${
        toneStyles[tone]
      }`}
    >
      <div className="flex items-center gap-1.5 text-xs font-medium">
        <Icon className="h-3.5 w-3.5" />
        {label}
      </div>

      <p className="text-sm font-semibold">{value}</p>
    </div>
  );
}