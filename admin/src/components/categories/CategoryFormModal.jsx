import { useState, useEffect } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { X } from "lucide-react";
import { CATEGORY_STATUS } from "../../data/serviceCategories";

const emptyForm = {
  name: "",
  description: "",
  status: CATEGORY_STATUS.ACTIVE,
};

export default function CategoryFormModal({
  open,
  mode = "add", // "add" | "edit"
  initialData,
  existingNames = [],
  onClose,
  onSubmit,
}) {
  const [form, setForm] = useState(emptyForm);
  const [error, setError] = useState("");

  useEffect(() => {
    if (open) {
      setForm(
        mode === "edit" && initialData
          ? {
              name: initialData.name ?? "",
              description: initialData.description ?? "",
              status: initialData.status ?? CATEGORY_STATUS.ACTIVE,
            }
          : emptyForm
      );
      setError("");
    }
  }, [open, mode, initialData]);

  if (!open) return null;

  const handleChange = (field) => (e) =>
    setForm((prev) => ({ ...prev, [field]: e.target.value }));

  const handleSubmit = (e) => {
    e.preventDefault();

    const trimmedName = form.name.trim();
    const trimmedDescription = form.description.trim();

    if (!trimmedName) {
      setError("Category name is required.");
      return;
    }
    if (!trimmedDescription) {
      setError("Description is required.");
      return;
    }

    const isDuplicate = existingNames.some(
      (name) =>
        name.trim().toLowerCase() === trimmedName.toLowerCase() &&
        (mode !== "edit" || name.trim().toLowerCase() !== (initialData?.name ?? "").trim().toLowerCase())
    );
    if (isDuplicate) {
      setError("A category with this name already exists.");
      return;
    }

    setError("");
    onSubmit({
      name: trimmedName,
      description: trimmedDescription,
      status: form.status,
    });
  };

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
          className="bg-white rounded-2xl shadow-xl w-full max-w-md"
        >
          <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
            <h2 className="text-lg font-semibold text-gray-800">
              {mode === "edit" ? "Edit Service Category" : "Add Service Category"}
            </h2>
            <button
              type="button"
              onClick={onClose}
              className="p-2 rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors"
            >
              <X size={18} />
            </button>
          </div>

          <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4">
            <div>
              <label className="text-xs text-gray-400 mb-1 block">
                Category Name
              </label>
              <input
                type="text"
                value={form.name}
                onChange={handleChange("name")}
                placeholder="e.g. Plumbing"
                className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
              />
            </div>

            <div>
              <label className="text-xs text-gray-400 mb-1 block">
                Description
              </label>
              <textarea
                value={form.description}
                onChange={handleChange("description")}
                rows={3}
                placeholder="Briefly describe this service category..."
                className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400 resize-none"
              />
            </div>

            <div>
              <label className="text-xs text-gray-400 mb-1 block">Status</label>
              <select
                value={form.status}
                onChange={handleChange("status")}
                className="w-full px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500/40 focus:border-blue-400"
              >
                {Object.values(CATEGORY_STATUS).map((opt) => (
                  <option key={opt} value={opt}>
                    {opt}
                  </option>
                ))}
              </select>
            </div>

            {error && (
              <p className="text-sm text-red-500 bg-red-50 border border-red-100 rounded-xl px-3 py-2">
                {error}
              </p>
            )}

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="px-3 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                className="px-3 py-2 rounded-xl bg-blue-600 text-sm text-white hover:bg-blue-700 transition-colors"
              >
                {mode === "edit" ? "Save Changes" : "Add Category"}
              </button>
            </div>
          </form>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
