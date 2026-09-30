import { useEffect, useMemo, useState } from "react";
import toast from "react-hot-toast";
import { motion } from "framer-motion";
import {
  ClipboardList,
  Clock3,
  Search as SearchIcon,
  CheckCircle2,
  XCircle,
} from "lucide-react";

import WorkerVerificationFilters from "../../components/verification/WorkerVerificationFilters";
import WorkerVerificationTable from "../../components/verification/WorkerVerificationTable";
import WorkerVerificationModal from "../../components/verification/WorkerVerificationModal";
import { VERIFICATION_STATUS } from "../../data/workerVerification";
import { apiRequest } from "../../lib/api";

const SUMMARY_CONFIG = [
  { key: "total", label: "Total Submissions", icon: ClipboardList, color: "blue" },
  { key: VERIFICATION_STATUS.PENDING, label: "Pending Review", icon: Clock3, color: "amber" },
  {
    key: VERIFICATION_STATUS.UNDER_REVIEW,
    label: "Under Review",
    icon: SearchIcon,
    color: "indigo",
  },
  {
    key: VERIFICATION_STATUS.VERIFIED,
    label: "Verified",
    icon: CheckCircle2,
    color: "green",
  },
  { key: VERIFICATION_STATUS.REJECTED, label: "Rejected", icon: XCircle, color: "red" },
];

const COLOR_STYLES = {
  blue: "bg-blue-50 text-blue-600",
  amber: "bg-amber-50 text-amber-600",
  indigo: "bg-indigo-50 text-indigo-600",
  green: "bg-green-50 text-green-600",
  red: "bg-red-50 text-red-500",
};

export default function WorkerVerification() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [searchTerm, setSearchTerm] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");
  const [categoryFilter, setCategoryFilter] = useState("All");
  const [idFilter, setIdFilter] = useState("All");
  const [faceFilter, setFaceFilter] = useState("All");
  const [selectedRequest, setSelectedRequest] = useState(null);

  useEffect(() => {
    apiRequest("/api/admin/verifications")
      .then(({ items }) => setRequests(items))
      .catch((loadError) => setError(loadError.message))
      .finally(() => setLoading(false));
  }, []);

  const categoryOptions = useMemo(() => {
    const set = new Set(requests.map((r) => r?.category).filter(Boolean));
    return Array.from(set).sort();
  }, [requests]);

  const summaryCounts = useMemo(() => {
    const counts = {
      total: requests.length,
      [VERIFICATION_STATUS.PENDING]: 0,
      [VERIFICATION_STATUS.UNDER_REVIEW]: 0,
      [VERIFICATION_STATUS.VERIFIED]: 0,
      [VERIFICATION_STATUS.REJECTED]: 0,
      [VERIFICATION_STATUS.RESUBMISSION_REQUIRED]: 0,
    };
    requests.forEach((r) => {
      if (r?.status && counts[r.status] !== undefined) {
        counts[r.status] += 1;
      }
    });
    return counts;
  }, [requests]);

  const filteredRequests = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();

    return requests.filter((r) => {
      const matchesSearch =
        !term ||
        [r?.workerId, r?.workerName, r?.verificationId, r?.category]
          .filter(Boolean)
          .some((field) => field.toLowerCase().includes(term));

      const matchesStatus = statusFilter === "All" || r?.status === statusFilter;
      const matchesCategory =
        categoryFilter === "All" || r?.category === categoryFilter;

      const matchesId =
        idFilter === "All" ||
        (idFilter === "Submitted" && r?.idSubmitted) ||
        (idFilter === "Not Submitted" && !r?.idSubmitted);

      const matchesFace =
        faceFilter === "All" ||
        (faceFilter === "Passed" && r?.faceVerified) ||
        (faceFilter === "Not Verified" && !r?.faceVerified);

      return (
        matchesSearch &&
        matchesStatus &&
        matchesCategory &&
        matchesId &&
        matchesFace
      );
    });
  }, [requests, searchTerm, statusFilter, categoryFilter, idFilter, faceFilter]);

  const handleClearFilters = () => {
    setSearchTerm("");
    setStatusFilter("All");
    setCategoryFilter("All");
    setIdFilter("All");
    setFaceFilter("All");
  };

  const handleViewDetails = async (request) => {
    try {
      const { item } = await apiRequest(`/api/admin/verifications/${request.workerId}`);
      setSelectedRequest(item);
    } catch (detailError) {
      toast.error(detailError.message);
    }
  };

  const handleUpdateRequest = async (verificationId, updates) => {
    const current = requests.find((request) => request.verificationId === verificationId);
    const { item } = await apiRequest(`/api/admin/verifications/${current.workerId}`, {
      method: "PATCH",
      body: JSON.stringify({ status: updates.status, adminNotes: updates.adminNotes }),
    });
    setRequests((prev) =>
      prev.map((r) =>
        r.verificationId === verificationId ? { ...r, ...item } : r
      )
    );
    return item;
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-gray-800">
          Worker Verification
        </h1>
        <p className="text-sm text-gray-500 mt-1">
          Review and manage worker verification submissions.
        </p>
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
      <WorkerVerificationFilters
        searchTerm={searchTerm}
        onSearchChange={setSearchTerm}
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
        categoryFilter={categoryFilter}
        onCategoryChange={setCategoryFilter}
        categoryOptions={categoryOptions}
        idFilter={idFilter}
        onIdFilterChange={setIdFilter}
        faceFilter={faceFilter}
        onFaceFilterChange={setFaceFilter}
        onClearFilters={handleClearFilters}
      />

      {/* Table */}
      {loading && <div className="bg-white rounded-2xl p-8 text-center text-gray-400">Loading verification requests…</div>}
      {error && <div className="bg-red-50 text-red-700 rounded-2xl p-4 mb-4">{error}</div>}
      <WorkerVerificationTable
        requests={filteredRequests}
        onViewDetails={handleViewDetails}
      />

      {/* Details Modal */}
      {selectedRequest && (
        <WorkerVerificationModal
          request={selectedRequest}
          onClose={() => setSelectedRequest(null)}
          onUpdate={handleUpdateRequest}
        />
      )}
    </div>
  );
}
