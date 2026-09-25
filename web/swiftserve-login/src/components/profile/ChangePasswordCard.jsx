import { useState } from "react";
import { motion } from "framer-motion";
import toast from "react-hot-toast";
import { Lock, Eye, EyeOff, KeyRound } from "lucide-react";

const initialForm = {
  currentPassword: "",
  newPassword: "",
  confirmPassword: "",
};

export default function ChangePasswordCard() {
  const [form, setForm] = useState(initialForm);
  const [visibility, setVisibility] = useState({
    currentPassword: false,
    newPassword: false,
    confirmPassword: false,
  });

  const handleChange = (field) => (e) =>
    setForm((prev) => ({ ...prev, [field]: e.target.value }));

  const toggleVisibility = (field) =>
    setVisibility((prev) => ({ ...prev, [field]: !prev[field] }));

  const handleSubmit = (e) => {
    e.preventDefault();

    if (!form.currentPassword || !form.newPassword || !form.confirmPassword) {
      toast.error("All password fields are required.");
      return;
    }

    if (form.newPassword.length < 8) {
      toast.error("New password must be at least 8 characters long.");
      return;
    }

    if (form.newPassword !== form.confirmPassword) {
      toast.error("New password and confirmation do not match.");
      return;
    }

    // TODO: Replace with an API call to change the admin password.
    // This prototype has no backend, so no password is actually changed.
    toast.success("Password changed successfully.");
    setForm(initialForm);
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2, delay: 0.05 }}
      className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5"
    >
      <div className="flex items-center gap-2 mb-4">
        <KeyRound size={16} className="text-gray-500" />
        <h3 className="text-sm font-semibold text-gray-700">
          Change Password
        </h3>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <PasswordField
          label="Current Password"
          value={form.currentPassword}
          visible={visibility.currentPassword}
          onToggleVisible={() => toggleVisibility("currentPassword")}
          onChange={handleChange("currentPassword")}
        />
        <PasswordField
          label="New Password"
          value={form.newPassword}
          visible={visibility.newPassword}
          onToggleVisible={() => toggleVisibility("newPassword")}
          onChange={handleChange("newPassword")}
          hint="Must be at least 8 characters."
        />
        <PasswordField
          label="Confirm New Password"
          value={form.confirmPassword}
          visible={visibility.confirmPassword}
          onToggleVisible={() => toggleVisibility("confirmPassword")}
          onChange={handleChange("confirmPassword")}
        />

        <div className="flex justify-end">
          <button
            type="submit"
            className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl bg-blue-600 text-sm text-white hover:bg-blue-700 transition-colors"
          >
            <Lock size={15} />
            Update Password
          </button>
        </div>
      </form>
    </motion.div>
  );
}

function PasswordField({ label, value, visible, onToggleVisible, onChange, hint }) {
  return (
    <div>
      <label className="text-xs text-gray-400 mb-1 block">{label}</label>
      <div className="relative">
        <input
          type={visible ? "text" : "password"}
          value={value}
          onChange={onChange}
          className="w-full px-3 py-2 pr-10 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
        />
        <button
          type="button"
          onClick={onToggleVisible}
          className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
          tabIndex={-1}
        >
          {visible ? <EyeOff size={16} /> : <Eye size={16} />}
        </button>
      </div>
      {hint && <p className="text-xs text-gray-400 mt-1">{hint}</p>}
    </div>
  );
}
