// src/data/bookings.js
// 45 static bookings referencing workers/clients/categories.

import { workers, clients, workerCategories } from './users'

export const STATUS = {
  COMPLETED: "Completed",
  ONGOING: "Ongoing",
  PENDING: "Pending",
  CANCELLED: "Cancelled",
};

export const CATEGORIES = workerCategories

const times = ['08:00 AM', '09:30 AM', '11:00 AM', '01:00 PM', '02:30 PM', '04:00 PM', '06:00 PM']

function pick(arr, seed) {
  return arr[seed % arr.length]
}

export const bookings = Array.from({ length: 45 }, (_, i) => {
  const seed = i + 1
  const worker = pick(workers, seed * 3)
  const client = pick(clients, seed * 5)
  const status = seed % 9 === 0 ? 'Cancelled' : seed % 4 === 0 ? 'Pending' : seed % 3 === 0 ? 'Ongoing' : 'Completed'
  const day = 1 + (seed % 27)
  return {
    id: `BKG-${String(5000 + seed)}`,
    client: client.name,
    worker: worker.name,
    category: pick(workerCategories, seed * 2),
    schedule: `2026-07-${String(day).padStart(2, '0')} · ${pick(times, seed)}`,
    status,
    amount: 350 + ((seed * 47) % 1800),
  }
})

export const bookingStatusCounts = bookings.reduce(
  (acc, b) => {
    acc[b.status] = (acc[b.status] || 0) + 1
    return acc
  },
  { Completed: 0, Ongoing: 0, Pending: 0, Cancelled: 0 },
)

export const latestBookings = bookings.slice(0, 8)
