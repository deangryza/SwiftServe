import { motion } from "framer-motion";
import { ShieldCheck, CalendarDays, Clock, Monitor } from "lucide-react";

export default function AccountInfoCard({ profile }) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2, delay: 0.1 }}
      className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5"
    >
      <h3 className="text-sm font-semibold text-gray-700 mb-4">
        Account & Session Information
      </h3>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <InfoItem
          icon={ShieldCheck}
          label="Account Status"
          value={profile.status}
          valueClassName="text-green-600 font-medium"
        />
        <InfoItem icon={ShieldCheck} label="Role" value={profile.role} />
        <InfoItem
          icon={CalendarDays}
          label="Account Created"
          value={profile.createdAt}
        />
        <InfoItem icon={Clock} label="Last Login" value={profile.lastLogin} />
        <InfoItem
          icon={Monitor}
          label="Current Session / Device"
          value={profile.device}
        />
      </div>

      <p className="text-xs text-gray-400 mt-4">
        Session and login details are placeholder values for this prototype.
        Real session tracking will be added once authentication is connected.
      </p>
    </motion.div>
  );
}

function InfoItem({ icon: Icon, label, value, valueClassName }) {
  return (
    <div className="flex items-start gap-2.5">
      <Icon size={15} className="text-gray-400 mt-0.5 shrink-0" />
      <div>
        <p className="text-xs text-gray-400">{label}</p>
        <p className={`text-sm text-gray-700 ${valueClassName ?? ""}`}>
          {value ?? "—"}
        </p>
      </div>
    </div>
  );
}
