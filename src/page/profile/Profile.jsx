import { useState } from "react";
import { motion } from "framer-motion";

import PersonalInfoCard from "../../components/profile/PersonalInfoCard";
import ChangePasswordCard from "../../components/profile/ChangePasswordCard";
import AccountInfoCard from "../../components/profile/AccountInfoCard";
import { adminProfile as initialProfile } from "../../data/adminProfile";

// TODO: Replace static admin profile data with API/database data
// once authentication and an admin accounts table exist.

export default function Profile() {
  const [profile, setProfile] = useState(initialProfile);

  const handleSavePersonalInfo = (updatedFields) => {
    setProfile((prev) => ({ ...prev, ...updatedFields }));
  };

  const fullName = `${profile.firstName} ${profile.lastName}`;

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-gray-800">
          Profile Settings
        </h1>
        <p className="text-sm text-gray-500 mt-1">
          Manage your administrator profile, security, and account details.
        </p>
      </div>

      {/* Profile Overview */}
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
        className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 mb-6 flex flex-col sm:flex-row sm:items-center gap-4"
      >
        <div className="w-16 h-16 rounded-2xl bg-blue-600 text-white flex items-center justify-center text-xl font-semibold shrink-0">
          {profile.avatarInitials}
        </div>

        <div className="flex-1">
          <h2 className="text-lg font-semibold text-gray-800">{fullName}</h2>
          <p className="text-sm text-gray-500">{profile.email}</p>
          <div className="flex items-center gap-2 mt-2">
            <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-blue-50 text-blue-600 border border-blue-200">
              {profile.role}
            </span>
            <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-green-50 text-green-600 border border-green-200">
              {profile.status}
            </span>
          </div>
        </div>
      </motion.div>

      {/* Content grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="space-y-6">
          <PersonalInfoCard profile={profile} onSave={handleSavePersonalInfo} />
          <ChangePasswordCard />
        </div>

        <div>
          <AccountInfoCard profile={profile} />
        </div>
      </div>
    </div>
  );
}
