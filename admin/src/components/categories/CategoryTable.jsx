import { motion } from "framer-motion";
import { Pencil, Power, Trash2, Users, ClipboardList, Calendar } from "lucide-react";
import { CATEGORY_STATUS } from "../../data/serviceCategories";

const STATUS_STYLES = {
  [CATEGORY_STATUS.ACTIVE]: "bg-green-50 text-green-600 border border-green-200",
  [CATEGORY_STATUS.INACTIVE]: "bg-gray-100 text-gray-500 border border-gray-200",
};

function StatusBadge({ status }) {
  const style =
    STATUS_STYLES[status] || "bg-gray-50 text-gray-500 border border-gray-200";
  return (
    <span
      className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${style}`}
    >
      {status || "Unknown"}
    </span>
  );
}

export default function CategoryTable({
  categories,
  onEdit,
  onToggleStatus,
  onDelete,
}) {
  if (!categories || categories.length === 0) {
    return (
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-10 text-center text-gray-400 text-sm">
        No service categories match your current filters.
      </div>
    );
  }

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm min-w-[900px]">
          <thead>
            <tr className="bg-gray-50 text-gray-500 text-xs uppercase tracking-wide">
              <th className="text-left font-medium px-4 py-3">Category</th>
              <th className="text-left font-medium px-4 py-3">Description</th>
              <th className="text-left font-medium px-4 py-3">Workers</th>
              <th className="text-left font-medium px-4 py-3">Bookings</th>
              <th className="text-left font-medium px-4 py-3">Status</th>
              <th className="text-left font-medium px-4 py-3">Date Created</th>
              <th className="text-right font-medium px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {categories.map((c, idx) => {
              const isActive = c?.status === CATEGORY_STATUS.ACTIVE;
              return (
                <motion.tr
                  key={c?.id ?? idx}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 0.2, delay: idx * 0.02 }}
                  className="hover:bg-gray-50/70 transition-colors"
                >
                  <td className="px-4 py-3 font-medium text-gray-800">
                    {c?.name ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-500 max-w-[280px] truncate">
                    {c?.description ?? "—"}
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    <span className="inline-flex items-center gap-1">
                      <Users size={13} className="text-gray-400" />
                      {c?.workerCount ?? 0}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-700">
                    <span className="inline-flex items-center gap-1">
                      <ClipboardList size={13} className="text-gray-400" />
                      {c?.bookingCount ?? 0}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge status={c?.status} />
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    <span className="inline-flex items-center gap-1">
                      <Calendar size={13} className="text-gray-400" />
                      {c?.dateCreated ?? "—"}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-2">
                      <button
                        type="button"
                        onClick={() => onEdit(c)}
                        title="Edit"
                        className="p-2 rounded-lg text-gray-500 hover:bg-blue-50 hover:text-blue-600 transition-colors"
                      >
                        <Pencil size={16} />
                      </button>
                      <button
                        type="button"
                        onClick={() => onToggleStatus(c)}
                        title={isActive ? "Deactivate" : "Activate"}
                        className={`p-2 rounded-lg transition-colors ${
                          isActive
                            ? "text-gray-500 hover:bg-amber-50 hover:text-amber-600"
                            : "text-gray-500 hover:bg-green-50 hover:text-green-600"
                        }`}
                      >
                        <Power size={16} />
                      </button>
                      <button
                        type="button"
                        onClick={() => onDelete(c)}
                        title="Delete"
                        className="p-2 rounded-lg text-gray-500 hover:bg-red-50 hover:text-red-600 transition-colors"
                      >
                        <Trash2 size={16} />
                      </button>
                    </div>
                  </td>
                </motion.tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
