import { useState } from "react";
import { motion } from "framer-motion";
import toast from "react-hot-toast";
import { Pencil, Save, X, User, Mail, Phone, Shield } from "lucide-react";

export default function PersonalInfoCard({ profile, onSave }) {
  const [isEditing, setIsEditing] = useState(false);
  const [form, setForm] = useState({
    firstName: profile.firstName,
    lastName: profile.lastName,
    email: profile.email,
    phone: profile.phone,
  });

  const handleChange = (field) => (e) =>
    setForm((prev) => ({ ...prev, [field]: e.target.value }));

  const handleEdit = () => {
    setForm({
      firstName: profile.firstName,
      lastName: profile.lastName,
      email: profile.email,
      phone: profile.phone,
    });
    setIsEditing(true);
  };

  const handleCancel = () => {
    setForm({
      firstName: profile.firstName,
      lastName: profile.lastName,
      email: profile.email,
      phone: profile.phone,
    });
    setIsEditing(false);
  };

  const handleSave = () => {
    if (!form.firstName.trim() || !form.lastName.trim() || !form.email.trim()) {
      toast.error("First name, last name, and email are required.");
      return;
    }

    // TODO: Replace with an API call to update the admin profile.
    onSave(form);
    setIsEditing(false);
    toast.success("Profile updated successfully.");
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5"
    >
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-gray-700">
          Personal Information
        </h3>
        {!isEditing && (
          <button
            type="button"
            onClick={handleEdit}
            className="inline-flex items-center gap-1.5 text-sm text-blue-600 hover:text-blue-700 font-medium"
          >
            <Pencil size={14} />
            Edit Profile
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Field
          icon={User}
          label="First Name"
          value={form.firstName}
          editable={isEditing}
          onChange={handleChange("firstName")}
        />
        <Field
          icon={User}
          label="Last Name"
          value={form.lastName}
          editable={isEditing}
          onChange={handleChange("lastName")}
        />
        <Field
          icon={Mail}
          label="Email Address"
          value={form.email}
          editable={isEditing}
          type="email"
          onChange={handleChange("email")}
        />
        <Field
          icon={Phone}
          label="Phone Number"
          value={form.phone}
          editable={isEditing}
          onChange={handleChange("phone")}
        />
        <Field
          icon={Shield}
          label="Role"
          value={profile.role}
          editable={false}
        />
      </div>

      {isEditing && (
        <div className="flex justify-end gap-2 mt-5">
          <button
            type="button"
            onClick={handleCancel}
            className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50 transition-colors"
          >
            <X size={15} />
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl bg-blue-600 text-sm text-white hover:bg-blue-700 transition-colors"
          >
            <Save size={15} />
            Save Changes
          </button>
        </div>
      )}
    </motion.div>
  );
}

function Field({ icon: Icon, label, value, editable, type = "text", onChange }) {
  return (
    <div>
      <label className="flex items-center gap-1.5 text-xs text-gray-400 mb-1">
        <Icon size={13} />
        {label}
      </label>
      {editable ? (
        <input
          type={type}
          value={value}
          onChange={onChange}
          className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
        />
      ) : (
        <p className="text-sm text-gray-700 px-3 py-2 rounded-xl bg-gray-50">
          {value ?? "—"}
        </p>
      )}
    </div>
  );
}
