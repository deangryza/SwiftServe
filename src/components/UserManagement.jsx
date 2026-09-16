import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import {
  Users,
  CheckCircle2,
  Clock,
  XCircle,
  Ban,
} from "lucide-react";
import toast from "react-hot-toast";

import { allUsers as initialUsers } from "../data/users";
import UserFilters from "./UserFilters";
import UserTable from "./UserTable";
import UserDetailsModal from "./UserDetailsModal";

const SUMMARY_CONFIG = [
  {
    key: "Total",
    label: "Total Users",
    icon: Users,
    color: "text-blue-600 bg-blue-50",
  },
  {
    key: "Approved",
    label: "Approved",
    icon: CheckCircle2,
    color: "text-green-600 bg-green-50",
  },
  {
    key: "Pending",
    label: "Pending",
    icon: Clock,
    color: "text-orange-600 bg-orange-50",
  },
  {
    key: "Rejected",
    label: "Rejected",
    icon: XCircle,
    color: "text-red-600 bg-red-50",
  },
  {
    key: "Suspended",
    label: "Suspended",
    icon: Ban,
    color: "text-gray-600 bg-gray-100",
  },
];

export default function UserManagement() {
  // Make sure the imported data is always an array
  const [userList, setUserList] = useState(
    Array.isArray(initialUsers) ? initialUsers : []
  );

  const [searchTerm, setSearchTerm] = useState("");
  const [roleFilter, setRoleFilter] = useState("All");
  const [statusFilter, setStatusFilter] = useState("All");
  const [selectedUser, setSelectedUser] = useState(null);

  // ----------------------------------------
  // SUMMARY COUNTS
  // ----------------------------------------

  const counts = useMemo(() => {
    return {
      Total: userList.length,

      Approved: userList.filter(
        (user) => user?.status === "Approved"
      ).length,

      Pending: userList.filter(
        (user) => user?.status === "Pending"
      ).length,

      Rejected: userList.filter(
        (user) => user?.status === "Rejected"
      ).length,

      Suspended: userList.filter(
        (user) => user?.status === "Suspended"
      ).length,
    };
  }, [userList]);

  // ----------------------------------------
  // SEARCH + FILTER
  // ----------------------------------------

  const filteredUsers = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();

    return userList.filter((user) => {
      const fullName = String(user?.fullName ?? "").toLowerCase();
      const email = String(user?.email ?? "").toLowerCase();
      const phone = String(user?.phone ?? "")
        .replace(/\s/g, "")
        .toLowerCase();

      const normalizedSearchPhone = term.replace(/\s/g, "");

      const matchesSearch =
        !term ||
        fullName.includes(term) ||
        email.includes(term) ||
        phone.includes(normalizedSearchPhone);

      const matchesRole =
        roleFilter === "All" ||
        String(user?.role ?? "") === roleFilter;

      const matchesStatus =
        statusFilter === "All" ||
        String(user?.status ?? "") === statusFilter;

      return matchesSearch && matchesRole && matchesStatus;
    });
  }, [userList, searchTerm, roleFilter, statusFilter]);

  // ----------------------------------------
  // STATUS UPDATE
  // ----------------------------------------

  const updateStatus = (user, newStatus, message) => {
    if (!user) return;

    setUserList((previousUsers) =>
      previousUsers.map((currentUser) =>
        currentUser?.id === user?.id
          ? {
              ...currentUser,
              status: newStatus,
            }
          : currentUser
      )
    );

    toast.success(message);
  };

  const handleApprove = (user) => {
    updateStatus(
      user,
      "Approved",
      `${user?.fullName ?? "User"} has been approved.`
    );
  };

  const handleReject = (user) => {
    updateStatus(
      user,
      "Rejected",
      `${user?.fullName ?? "User"} has been rejected.`
    );
  };

  const handleSuspend = (user) => {
    updateStatus(
      user,
      "Suspended",
      `${user?.fullName ?? "User"} has been suspended.`
    );
  };

  const handleReactivate = (user) => {
    updateStatus(
      user,
      "Approved",
      `${user?.fullName ?? "User"} has been reactivated.`
    );
  };

  // ----------------------------------------
  // PAGE
  // ----------------------------------------

  return (
    <div className="space-y-6">
      {/* PAGE HEADER */}
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">
          User Management
        </h1>

        <p className="mt-1 text-sm text-gray-500">
          Review, verify, and manage all registered clients and workers.
        </p>
      </div>

      {/* SUMMARY CARDS */}
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        {SUMMARY_CONFIG.map((card, index) => {
          const Icon = card.icon;

          return (
            <motion.div
              key={card.key}
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{
                duration: 0.25,
                delay: index * 0.05,
              }}
              className="rounded-xl bg-white p-4 shadow-sm ring-1 ring-gray-100"
            >
              <div
                className={`mb-3 inline-flex rounded-lg p-2 ${card.color}`}
              >
                <Icon className="h-5 w-5" />
              </div>

              <p className="text-2xl font-semibold text-gray-900">
                {counts[card.key]}
              </p>

              <p className="text-xs text-gray-500">
                {card.label}
              </p>
            </motion.div>
          );
        })}
      </div>

      {/* FILTERS */}
      <UserFilters
        searchTerm={searchTerm}
        onSearchChange={setSearchTerm}
        roleFilter={roleFilter}
        onRoleChange={setRoleFilter}
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
      />

      {/* USER TABLE */}
      <UserTable
        users={filteredUsers}
        onView={setSelectedUser}
        onApprove={handleApprove}
        onReject={handleReject}
        onSuspend={handleSuspend}
        onReactivate={handleReactivate}
      />

      {/* USER DETAILS MODAL */}
      <UserDetailsModal
        user={selectedUser}
        onClose={() => setSelectedUser(null)}
      />
    </div>
  );
}