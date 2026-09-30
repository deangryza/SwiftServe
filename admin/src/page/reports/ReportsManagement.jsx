import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import {
  ClipboardList,
  Clock3,
  Search as SearchIcon,
  CheckCircle2,
  AlertTriangle,
} from "lucide-react";

import ReportFilters from "../../components/reports/ReportFilters";
import ReportTable from "../../components/reports/ReportTable";
import ReportDetailsModal from "../../components/reports/ReportDetailsModal";
import { reports as initialReports, REPORT_STATUS } from "../../data/reports";

// TODO: Replace static reports data with API/database data.
// e.g. useEffect(() => { fetchReports().then(setReports) }, []);

const SUMMARY_CONFIG = [
  { key: "total", label: "Total Reports", icon: ClipboardList, color: "blue" },
  { key: REPORT_STATUS.PENDING, label: "Pending", icon: Clock3, color: "amber" },
  {
    key: REPORT_STATUS.UNDER_REVIEW,
    label: "Under Review",
    icon: SearchIcon,
    color: "indigo",
  },
  {
    key: REPORT_STATUS.RESOLVED,
    label: "Resolved",
    icon: CheckCircle2,
    color: "green",
  },
  { key: "highPriority", label: "High Priority", icon: AlertTriangle, color: "red" },
];

const COLOR_STYLES = {
  blue: "bg-blue-50 text-blue-600",
  amber: "bg-amber-50 text-amber-600",
  indigo: "bg-indigo-50 text-indigo-600",
  green: "bg-green-50 text-green-600",
  red: "bg-red-50 text-red-500",
};

export default function ReportsManagement() {
  const [reports, setReports] = useState(initialReports);
  const [searchTerm, setSearchTerm] = useState("");
  const [statusFilter, setStatusFilter] = useState("All");
  const [typeFilter, setTypeFilter] = useState("All");
  const [priorityFilter, setPriorityFilter] = useState("All");
  const [selectedReport, setSelectedReport] = useState(null);

  const summaryCounts = useMemo(() => {
    const counts = {
      total: reports.length,
      [REPORT_STATUS.PENDING]: 0,
      [REPORT_STATUS.UNDER_REVIEW]: 0,
      [REPORT_STATUS.RESOLVED]: 0,
      [REPORT_STATUS.DISMISSED]: 0,
      highPriority: 0,
    };
    reports.forEach((r) => {
      if (r?.status && counts[r.status] !== undefined) {
        counts[r.status] += 1;
      }
      if (r?.priority === "High") {
        counts.highPriority += 1;
      }
    });
    return counts;
  }, [reports]);

  const filteredReports = useMemo(() => {
    const term = searchTerm.trim().toLowerCase();

    return reports.filter((r) => {
      const matchesSearch =
        !term ||
        [r?.id, r?.subject, r?.reporter, r?.reportedUser]
          .filter(Boolean)
          .some((field) => field.toLowerCase().includes(term));

      const matchesStatus = statusFilter === "All" || r?.status === statusFilter;
      const matchesType = typeFilter === "All" || r?.reportType === typeFilter;
      const matchesPriority =
        priorityFilter === "All" || r?.priority === priorityFilter;

      return matchesSearch && matchesStatus && matchesType && matchesPriority;
    });
  }, [reports, searchTerm, statusFilter, typeFilter, priorityFilter]);

  const handleClearFilters = () => {
    setSearchTerm("");
    setStatusFilter("All");
    setTypeFilter("All");
    setPriorityFilter("All");
  };

  const handleSaveReport = (reportId, updates) => {
    setReports((prev) =>
      prev.map((r) => (r.id === reportId ? { ...r, ...updates } : r))
    );
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-gray-800">
          Reports & Complaints
        </h1>
        <p className="text-sm text-gray-500 mt-1">
          Review and resolve reports and complaints submitted by clients and
          service providers.
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
      <ReportFilters
        searchTerm={searchTerm}
        onSearchChange={setSearchTerm}
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
        typeFilter={typeFilter}
        onTypeChange={setTypeFilter}
        priorityFilter={priorityFilter}
        onPriorityChange={setPriorityFilter}
        onClearFilters={handleClearFilters}
      />

      {/* Table */}
      <ReportTable reports={filteredReports} onViewDetails={setSelectedReport} />

      {/* Details Modal */}
      {selectedReport && (
        <ReportDetailsModal
          report={selectedReport}
          onClose={() => setSelectedReport(null)}
          onSave={handleSaveReport}
        />
      )}
    </div>
  );
}
