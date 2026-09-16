import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import toast from "react-hot-toast";
import { Tags, CheckCircle2, XCircle, Users, ClipboardList, Plus } from "lucide-react";

import CategoryFilters from "../../components/categories/CategoryFilters";
import CategoryTable from "../../components/categories/CategoryTable";
import CategoryFormModal from "../../components/categories/CategoryFormModal";
import ConfirmDialog from "../../components/categories/ConfirmDialog";
import {
  serviceCategories as initialCategories,
  CATEGORY_STATUS,
} from "../../data/serviceCategories";

// TODO: Replace static category data with API/database data, and replace
// workerCount / bookingCount with live counts derived from the real
// users.js / bookings.js once their structure is confirmed.

const SUMMARY_CONFIG = [
  { key: "total", label: "Total Categories", icon: Tags, color: "blue" },
  { key: "active", label: "Active Categories", icon: CheckCircle2, color: "green" },
  { key: "inactive", label: "Inactive Categories", icon: XCircle, color: "gray" },
  { key: "totalWorkers", label: "Total Workers", icon: Users, color: "indigo" },
  { key: "totalBookings", label: "Total Bookings", icon: ClipboardList, color: "amber" },
];

const COLOR_STYLES = {
  blue: "bg-blue-50 text-blue-600",
  green: "bg-green-50 text-green-600",
  gray: "bg-gray-100 text-gray-500",
  indigo: "bg-indigo-50 text-indigo-600",
  amber: "bg-amber-50 text-amber-600",
};

export default function ServiceCategories() {
  const [categories, setCategories] = useState(initialCategories);
  const [searchTerm, setSearchTerm] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");

  const [formOpen, setFormOpen] = useState(false);
  const [formMode, setFormMode] = useState("add");
  const [editingCategory, setEditingCategory] = useState(null);

  const [confirmState, setConfirmState] = useState(null);
  // confirmState shape: { type: "delete" | "toggle", category }

  const summaryCounts = useMemo(() => {
    return categories.reduce(
      (acc, c) => {
        acc.total += 1;
        if (c?.status === CATEGORY_STATUS.ACTIVE) acc.active += 1;
        if (c?.status === CATEGORY_STATUS.INACTIVE) acc.inactive += 1;
        acc.totalWorkers += c?.workerCount ?? 0;
        acc.totalBookings += c?.bookingCount ?? 0;
        return acc;
      },
      { total: 0, active: 0, inactive: 0, totalWorkers: 0, totalBookings: 0 }
    );
  }, [categories]);

  const filteredCategories = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();

    return categories.filter((c) => {
      const matchesSearch =
        !term ||
        [c?.name, c?.description]
          .filter(Boolean)
          .some((field) => field.toLowerCase().includes(term));

      const matchesStatus = statusFilter === "All" || c?.status === statusFilter;

      return matchesSearch && matchesStatus;
    });
  }, [categories, searchTerm, statusFilter]);

  const handleClearFilters = () => {
    setSearchTerm("");
    setStatusFilter("All");
  };

  const handleOpenAdd = () => {
    setFormMode("add");
    setEditingCategory(null);
    setFormOpen(true);
  };

  const handleOpenEdit = (category) => {
    setFormMode("edit");
    setEditingCategory(category);
    setFormOpen(true);
  };

  const handleFormSubmit = (data) => {
    if (formMode === "edit" && editingCategory) {
      setCategories((prev) =>
        prev.map((c) =>
          c.id === editingCategory.id ? { ...c, ...data } : c
        )
      );
      toast.success("Service category updated successfully.");
    } else {
      const newCategory = {
        id: `CAT-${String(Date.now()).slice(-6)}`,
        ...data,
        workerCount: 0,
        bookingCount: 0,
        dateCreated: new Date().toISOString().slice(0, 10),
      };
      setCategories((prev) => [newCategory, ...prev]);
      toast.success("Service category added successfully.");
    }
    setFormOpen(false);
    setEditingCategory(null);
  };

  const handleRequestToggleStatus = (category) => {
    // Activating doesn't need confirmation; only deactivating does.
    if (category.status === CATEGORY_STATUS.ACTIVE) {
      setConfirmState({ type: "toggle", category });
    } else {
      applyToggleStatus(category);
    }
  };

  const applyToggleStatus = (category) => {
    const nextStatus =
      category.status === CATEGORY_STATUS.ACTIVE
        ? CATEGORY_STATUS.INACTIVE
        : CATEGORY_STATUS.ACTIVE;

    setCategories((prev) =>
      prev.map((c) => (c.id === category.id ? { ...c, status: nextStatus } : c))
    );

    toast.success(
      nextStatus === CATEGORY_STATUS.INACTIVE
        ? "Service category deactivated."
        : "Service category activated."
    );
  };

  const handleRequestDelete = (category) => {
    setConfirmState({ type: "delete", category });
  };

  const handleConfirm = () => {
    if (!confirmState) return;
    const { type, category } = confirmState;

    if (type === "toggle") {
      applyToggleStatus(category);
    } else if (type === "delete") {
      const hasDependents =
        (category.workerCount ?? 0) > 0 || (category.bookingCount ?? 0) > 0;

      if (hasDependents) {
        toast.error(
          "This category has existing workers or bookings and cannot be deleted. You can deactivate it instead."
        );
      } else {
        setCategories((prev) => prev.filter((c) => c.id !== category.id));
        toast.success("Service category deleted.");
      }
    }

    setConfirmState(null);
  };

  const confirmDialogProps = useMemo(() => {
    if (!confirmState) return { open: false };

    if (confirmState.type === "toggle") {
      return {
        open: true,
        title: "Deactivate Category",
        message: `Are you sure you want to deactivate "${confirmState.category.name}"? Existing workers and bookings will not be affected.`,
        confirmLabel: "Deactivate",
        confirmVariant: "danger",
      };
    }

    return {
      open: true,
      title: "Delete Category",
      message: `Are you sure you want to delete "${confirmState.category.name}"? This cannot be undone.`,
      confirmLabel: "Delete",
      confirmVariant: "danger",
    };
  }, [confirmState]);

  return (
    <div>
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-gray-800">
            Service Categories
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Manage the services available on the SwiftServe platform.
          </p>
        </div>
        <button
          type="button"
          onClick={handleOpenAdd}
          className="inline-flex items-center justify-center gap-1.5 px-4 py-2.5 rounded-xl bg-blue-600 text-sm text-white hover:bg-blue-700 transition-colors self-start sm:self-auto"
        >
          <Plus size={16} />
          Add Category
        </button>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4 mb-6">
        {SUMMARY_CONFIG.map((card, i) => {
          const Icon = card.icon;
          return (
            <motion.div
              key={card.key}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.2, delay: i * 0.03 }}
              className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4"
            >
              <div
                className={`w-9 h-9 rounded-xl flex items-center justify-center mb-3 ${COLOR_STYLES[card.color]}`}
              >
                <Icon size={18} />
              </div>
              <p className="text-xl font-semibold text-gray-800">
                {summaryCounts[card.key] ?? 0}
              </p>
              <p className="text-xs text-gray-500 mt-0.5">{card.label}</p>
            </motion.div>
          );
        })}
      </div>

      {/* Filters */}
      <CategoryFilters
        searchTerm={searchTerm}
        onSearchChange={setSearchTerm}
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
        onClearFilters={handleClearFilters}
      />

      {/* Table */}
      <CategoryTable
        categories={filteredCategories}
        onEdit={handleOpenEdit}
        onToggleStatus={handleRequestToggleStatus}
        onDelete={handleRequestDelete}
      />

      {/* Add/Edit Modal */}
      <CategoryFormModal
        open={formOpen}
        mode={formMode}
        initialData={editingCategory}
        existingNames={categories.map((c) => c.name)}
        onClose={() => {
          setFormOpen(false);
          setEditingCategory(null);
        }}
        onSubmit={handleFormSubmit}
      />

      {/* Confirm Dialog (deactivate / delete) */}
      <ConfirmDialog
        {...confirmDialogProps}
        onConfirm={handleConfirm}
        onCancel={() => setConfirmState(null)}
      />
    </div>
  );
}
