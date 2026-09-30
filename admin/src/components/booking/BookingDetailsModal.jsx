import { AnimatePresence, motion } from "framer-motion";
import {
  X,
  User,
  Briefcase,
  Mail,
  Phone,
  Star,
  MapPin,
  Calendar,
  Clock,
  CheckCircle2,
  Circle,
  XCircle,
} from "lucide-react";
import { STATUS } from "../../data/bookings";

const TIMELINE_STAGES = [
  "Request Created",
  "Provider Accepted",
  "Booking Confirmed",
  "Work Started",
  "Completed",
];

// How many timeline stages are considered "reached" for a given status.
function stagesReached(status) {
  switch (status) {
    case STATUS.PENDING:
      return 1;
    case STATUS.ACCEPTED:
      return 3;
    case STATUS.IN_PROGRESS:
      return 4;
    case STATUS.COMPLETED:
      return 5;
    default:
      return 0;
  }
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

export default function BookingDetailsModal({ booking, onClose }) {
  if (!booking) return null;

  const isCancelled = booking.status === STATUS.CANCELLED;
  const reached = stagesReached(booking.status);

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
                {booking.serviceTitle ?? "Booking Details"}
              </h2>
              <p className="text-xs text-gray-400">{booking.id ?? "—"}</p>
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
            {/* Booking Information */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Booking Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={Briefcase} label="Category" value={booking.category} />
                <InfoRow icon={Calendar} label="Date" value={booking.date} />
                <InfoRow icon={Clock} label="Time" value={booking.time} />
                <InfoRow icon={MapPin} label="Location" value={booking.location} />
              </div>
              {booking.description && (
                <p className="mt-3 text-sm text-gray-600 bg-gray-50 rounded-xl p-3">
                  {booking.description}
                </p>
              )}
            </section>

            {/* Client Info */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Client Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={User} label="Name" value={booking.clientName} />
                <InfoRow icon={Mail} label="Email" value={booking.clientEmail} />
                <InfoRow icon={Phone} label="Contact Number" value={booking.clientPhone} />
              </div>
            </section>

            {/* Provider Info */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Service Provider Information
              </h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <InfoRow icon={User} label="Name" value={booking.providerName} />
                <InfoRow icon={Mail} label="Email" value={booking.providerEmail} />
                <InfoRow icon={Phone} label="Contact Number" value={booking.providerPhone} />
                <InfoRow
                  icon={Star}
                  label="Rating"
                  value={
                    typeof booking.providerRating === "number"
                      ? `${booking.providerRating.toFixed(1)} / 5.0`
                      : "Not rated yet"
                  }
                />
              </div>
            </section>

            {/* Timeline */}
            <section>
              <h3 className="text-sm font-semibold text-gray-700 mb-3">
                Booking Timeline
              </h3>

              {isCancelled ? (
                <div className="flex items-center gap-2 text-sm text-red-500 bg-red-50 border border-red-100 rounded-xl px-3 py-2.5">
                  <XCircle size={16} />
                  This booking was cancelled before completion.
                </div>
              ) : (
                <ol className="space-y-3">
                  {TIMELINE_STAGES.map((stage, i) => {
                    const done = i < reached;
                    return (
                      <li key={stage} className="flex items-center gap-3">
                        {done ? (
                          <CheckCircle2 size={18} className="text-green-500 shrink-0" />
                        ) : (
                          <Circle size={18} className="text-gray-300 shrink-0" />
                        )}
                        <span
                          className={`text-sm ${
                            done ? "text-gray-700 font-medium" : "text-gray-400"
                          }`}
                        >
                          {stage}
                        </span>
                      </li>
                    );
                  })}
                </ol>
              )}
            </section>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
