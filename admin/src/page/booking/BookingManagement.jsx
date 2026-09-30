import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import toast from "react-hot-toast";
import {
  ClipboardList,
  Clock3,
  Loader2,
  CheckCircle2,
  Ban,
} from "lucide-react";

import { bookings as initialBookings, STATUS } from "../../data/bookings";

import BookingFilters from "../../components/booking/BookingFilters";
import BookingTable from "../../components/booking/BookingTable";
import BookingDetailsModal from "../../components/booking/BookingDetailsModal";

// TODO: Replace static booking data with API/database data.
// e.g. useEffect(() => { fetchBookings().then(setBookings) }, []);

const SUMMARY_CONFIG = [
  {
    key: "total",
    label: "Total Bookings",
    icon: ClipboardList,
    color: "blue",
  },
  {
    key: STATUS.PENDING,
    label: "Pending",
    icon: Clock3,
    color: "amber",
  },
  {
    key: STATUS.ONGOING,
    label: "Ongoing",
    icon: Loader2,
    color: "indigo",
  },
  {
    key: STATUS.COMPLETED,
    label: "Completed",
    icon: CheckCircle2,
    color: "green",
  },
  {
    key: STATUS.CANCELLED,
    label: "Cancelled",
    icon: Ban,
    color: "red",
  },
];
const COLOR_STYLES = {
  blue: "bg-blue-50 text-blue-600",
  amber: "bg-amber-50 text-amber-600",
  sky: "bg-sky-50 text-sky-600",
  indigo: "bg-indigo-50 text-indigo-600",
  green: "bg-green-50 text-green-600",
  red: "bg-red-50 text-red-500",
};

export default function BookingManagement() {
  const [bookings, setBookings] = useState(initialBookings);
  const [searchTerm, setSearchTerm] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");
  const [categoryFilter, setCategoryFilter] = useState("All");
  const [dateFilter, setDateFilter] = useState("");
  const [selectedBooking, setSelectedBooking] = useState(null);

  const summaryCounts = useMemo(() => {
    const counts = {
      total: bookings.length,
      [STATUS.PENDING]: 0,
      [STATUS.ONGOING]: 0,
      [STATUS.COMPLETED]: 0,
      [STATUS.CANCELLED]: 0,
    };
    bookings.forEach((b) => {
      if (b?.status && counts[b.status] !== undefined) {
        counts[b.status] += 1;
      }
    });
    return counts;
  }, [bookings]);

  const filteredBookings = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();

    return bookings.filter((b) => {
      const matchesSearch =
        !term ||
        [b?.id, b?.clientName, b?.providerName, b?.serviceTitle]
          .filter(Boolean)
          .some((field) => field.toLowerCase().includes(term));

      const matchesStatus = statusFilter === "All" || b?.status === statusFilter;
      const matchesCategory =
        categoryFilter === "All" || b?.category === categoryFilter;
      const matchesDate = !dateFilter || b?.date === dateFilter;

      return matchesSearch && matchesStatus && matchesCategory && matchesDate;
    });
  }, [bookings, searchTerm, statusFilter, categoryFilter, dateFilter]);

  const handleClearFilters = () => {
    setSearchTerm("");
    setStatusFilter("All");
    setCategoryFilter("All");
    setDateFilter("");
  };

  const handleCancel = (booking, mode) => {
    if (!booking?.id) return;

    if (mode === "override") {
      const confirmed = window.confirm(
        `"${booking.serviceTitle ?? "This booking"}" has already been accepted and confirmed. ` +
          `Cancelling now counts as an admin dispute override. Continue?`
      );
      if (!confirmed) return;
    }

    setBookings((prev) =>
      prev.map((b) =>
        b.id === booking.id ? { ...b, status: STATUS.CANCELLED } : b
      )
    );

    toast.success(
      mode === "override"
        ? `Booking ${booking.id} cancelled via admin override.`
        : `Booking ${booking.id} cancelled.`
    );
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-gray-800">
          Booking Management
        </h1>
        <p className="text-sm text-gray-500 mt-1">
          Monitor and manage all service bookings between clients and service
          providers.
        </p>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
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
      <BookingFilters
        searchTerm={searchTerm}
        onSearchChange={setSearchTerm}
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
        categoryFilter={categoryFilter}
        onCategoryChange={setCategoryFilter}
        dateFilter={dateFilter}
        onDateChange={setDateFilter}
        onClearFilters={handleClearFilters}
      />

      {/* Table */}
      <BookingTable
        bookings={filteredBookings}
        onViewDetails={setSelectedBooking}
        onCancel={handleCancel}
      />

      {/* Details Modal */}
      {selectedBooking && (
        <BookingDetailsModal
          booking={selectedBooking}
          onClose={() => setSelectedBooking(null)}
        />
      )}
    </div>
  );
}
