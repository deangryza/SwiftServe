// src/data/reports.js
// Static complaint/report records for the admin dashboard.

import { workers, clients } from "./users";

export const REPORT_STATUS = {
  PENDING: "Pending",
  UNDER_REVIEW: "Under Review",
  RESOLVED: "Resolved",
  DISMISSED: "Dismissed",
};

export const ADMIN_ACTIONS = [
  "No Action",
  "Warning Issued",
  "User Suspended",
  "Worker Suspended",
  "Report Escalated",
  "Account Restricted",
];

export const REPORT_TYPES = [
  "Service Complaint",
  "Payment Dispute",
  "User Report",
  "Worker Complaint",
];

export const PRIORITY_LEVELS = [
  "Low",
  "Medium",
  "High",
];

const reasons = [
  "Worker arrived late",
  "Payment dispute",
  "Unprofessional conduct",
  "Incomplete job",
  "Damaged property",
  "Overcharging",
  "No-show",
  "Poor service quality",
  "Inappropriate behavior",
  "Fake profile suspicion",
];

const reportTypes = [
  "Service Complaint",
  "Payment Dispute",
  "User Report",
  "Worker Complaint",
];

const priorities = ["Low", "Medium", "High"];

function pick(arr, seed) {
  return arr[seed % arr.length];
}

export const reports = Array.from({ length: 20 }, (_, i) => {
  const seed = i + 1;
  const day = 1 + (seed % 27);

  let status;

  if (seed % 5 === 0) {
    status = REPORT_STATUS.RESOLVED;
  } else if (seed % 4 === 0) {
    status = REPORT_STATUS.DISMISSED;
  } else if (seed % 3 === 0) {
    status = REPORT_STATUS.UNDER_REVIEW;
  } else {
    status = REPORT_STATUS.PENDING;
  }

  return {
    id: `RPT-${String(7000 + seed)}`,

    subject: pick(reasons, seed),

    reporter: pick(clients, seed * 4).name,

    reportedUser: pick(workers, seed * 6).name,

    reportType: pick(reportTypes, seed * 2),

    reason: pick(reasons, seed),

    priority: pick(priorities, seed * 3),

    status,

    date: `2026-06-${String(day).padStart(2, "0")}`,

    description:
      "The user submitted a report regarding an issue encountered during a service transaction.",

    adminNotes: "",
  };
});

export const reportStatusCounts = reports.reduce(
  (acc, report) => {
    acc[report.status] = (acc[report.status] || 0) + 1;
    return acc;
  },
  {
    [REPORT_STATUS.PENDING]: 0,
    [REPORT_STATUS.UNDER_REVIEW]: 0,
    [REPORT_STATUS.RESOLVED]: 0,
    [REPORT_STATUS.DISMISSED]: 0,
  }
);

export const recentReports = reports.slice(0, 8);