// TODO: workerCount and bookingCount are static placeholders for this
// prototype. Once the real structure of src/data/users.js and
// src/data/bookings.js is confirmed, replace these with live counts, e.g.:
//   const workerCount = workers.filter(w => w.category === category.name).length;
//   const bookingCount = bookings.filter(b => b.category === category.name).length;
//
// This file is intentionally kept separate from users.js / bookings.js so it
// does not conflict with any existing workerCategories array.

export const CATEGORY_STATUS = {
  ACTIVE: "Active",
  INACTIVE: "Inactive",
};

export const serviceCategories = [
  {
    id: "CAT-001",
    name: "Plumbing",
    description: "Basic plumbing assistance and household plumbing services.",
    workerCount: 12,
    bookingCount: 45,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-01-15",
  },
  {
    id: "CAT-002",
    name: "Electrical",
    description: "Minor household electrical repairs and installations.",
    workerCount: 9,
    bookingCount: 31,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-01-15",
  },
  {
    id: "CAT-003",
    name: "Aircon Repair",
    description: "Cleaning, maintenance, and basic repair of aircon units.",
    workerCount: 7,
    bookingCount: 28,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-01-18",
  },
  {
    id: "CAT-004",
    name: "House Cleaning",
    description: "General home cleaning, tidying, and organizing services.",
    workerCount: 18,
    bookingCount: 62,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-01-15",
  },
  {
    id: "CAT-005",
    name: "Carpentry",
    description: "Basic furniture repair, assembly, and small woodwork tasks.",
    workerCount: 6,
    bookingCount: 19,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-01-20",
  },
  {
    id: "CAT-006",
    name: "Appliance Repair",
    description: "Basic troubleshooting and repair of household appliances.",
    workerCount: 5,
    bookingCount: 14,
    status: CATEGORY_STATUS.INACTIVE,
    dateCreated: "2026-01-22",
  },
  {
    id: "CAT-007",
    name: "Painting",
    description: "Interior and exterior painting for homes and small spaces.",
    workerCount: 8,
    bookingCount: 22,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-01-25",
  },
  {
    id: "CAT-008",
    name: "Pest Control",
    description: "Basic pest inspection and household pest control services.",
    workerCount: 4,
    bookingCount: 11,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-02-01",
  },
  {
    id: "CAT-009",
    name: "Massage Therapy",
    description: "Home-service relaxation and therapeutic massage sessions.",
    workerCount: 10,
    bookingCount: 37,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-02-03",
  },
  {
    id: "CAT-010",
    name: "Gardening",
    description: "Lawn care, weeding, trimming, and basic garden upkeep.",
    workerCount: 6,
    bookingCount: 17,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-02-05",
  },
  {
    id: "CAT-011",
    name: "Car Wash",
    description: "Mobile car washing and basic detailing services.",
    workerCount: 3,
    bookingCount: 9,
    status: CATEGORY_STATUS.INACTIVE,
    dateCreated: "2026-02-10",
  },
  {
    id: "CAT-012",
    name: "Laundry Service",
    description: "Washing, drying, and folding services for households.",
    workerCount: 11,
    bookingCount: 40,
    status: CATEGORY_STATUS.ACTIVE,
    dateCreated: "2026-02-12",
  },
];
