// Destination: src/components/users/UserTable.jsx
import { motion } from "framer-motion";
import { Eye, Check, X, Ban, RotateCcw } from "lucide-react";
import StatusBadge from "./StatusBadge";

export default function UserTable({
  users,
  onView,
  onApprove,
  onReject,
  onSuspend,
  onReactivate,
}) {
  if (users.length === 0) {
    return (
      <div className="rounded-xl bg-white p-10 text-center text-sm text-gray-500 shadow-sm ring-1 ring-gray-100">
        No users match your search or filters.
      </div>
    );
  }

  return (
    <div className="overflow-x-auto rounded-xl bg-white shadow-sm ring-1 ring-gray-100">
      <table className="min-w-full divide-y divide-gray-100 text-sm">
        <thead className="bg-gray-50">
          <tr className="text-left text-xs font-semibold uppercase tracking-wide text-gray-500">
            <th className="px-4 py-3">Profile</th>
            <th className="px-4 py-3">Full Name</th>
            <th className="px-4 py-3">Role</th>
            <th className="px-4 py-3">Email</th>
            <th className="px-4 py-3">Phone</th>
            <th className="px-4 py-3">Verification</th>
            <th className="px-4 py-3">Registered</th>
            <th className="px-4 py-3 text-right">Action</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-50">
          {users.map((user, i) => (
            <motion.tr
              key={user.id}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.2, delay: i * 0.02 }}
              className="transition hover:bg-blue-50/40"
            >
              <td className="px-4 py-3">
                <img
                  src={user.profilePic}
                  alt={user.fullName}
                  className="h-9 w-9 rounded-full object-cover"
                />
              </td>
              <td className="whitespace-nowrap px-4 py-3 font-medium text-gray-800">
                {user.fullName}
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                {user.role}
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                {user.email}
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                {user.phone}
              </td>
              <td className="whitespace-nowrap px-4 py-3">
                <StatusBadge status={user.status} />
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-gray-600">
                {user.registrationDate}
              </td>
              <td className="whitespace-nowrap px-4 py-3">
                <div className="flex items-center justify-end gap-1.5">
                  <ActionButton
                    title="View profile"
                    onClick={() => onView(user)}
                    className="text-blue-600 hover:bg-blue-100"
                  >
                    <Eye className="h-4 w-4" />
                  </ActionButton>

                  {user.status === "Pending" && (
                    <>
                      <ActionButton
                        title="Approve"
                        onClick={() => onApprove(user)}
                        className="text-green-600 hover:bg-green-100"
                      >
                        <Check className="h-4 w-4" />
                      </ActionButton>
                      <ActionButton
                        title="Reject"
                        onClick={() => onReject(user)}
                        className="text-red-600 hover:bg-red-100"
                      >
                        <X className="h-4 w-4" />
                      </ActionButton>
                    </>
                  )}

                  {user.status === "Approved" && (
                    <ActionButton
                      title="Suspend"
                      onClick={() => onSuspend(user)}
                      className="text-gray-600 hover:bg-gray-100"
                    >
                      <Ban className="h-4 w-4" />
                    </ActionButton>
                  )}

                  {user.status === "Suspended" && (
                    <ActionButton
                      title="Reactivate"
                      onClick={() => onReactivate(user)}
                      className="text-blue-600 hover:bg-blue-100"
                    >
                      <RotateCcw className="h-4 w-4" />
                    </ActionButton>
                  )}
                </div>
              </td>
            </motion.tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ActionButton({ children, title, onClick, className }) {
  return (
    <button
      title={title}
      onClick={onClick}
      className={`rounded-lg p-1.5 transition ${className}`}
    >
      {children}
    </button>
  );
}
