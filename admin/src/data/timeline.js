// src/data/timeline.js
// 20 recent activity events across the platform.

import { workers, clients } from './users'

const eventTypes = [
  { type: 'worker_registered', label: 'registered as a new service provider' },
  { type: 'worker_verified', label: 'passed ID and face verification' },
  { type: 'booking_created', label: 'created a new booking request' },
  { type: 'booking_completed', label: 'completed a booking' },
  { type: 'complaint_submitted', label: 'submitted a complaint' },
  { type: 'account_suspended', label: 'account was suspended for policy violation' },
]

function pick(arr, seed) {
  return arr[seed % arr.length]
}

function minutesAgoLabel(mins) {
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  return `${days}d ago`
}

export const timelineEvents = Array.from({ length: 20 }, (_, i) => {
  const seed = i + 1
  const event = pick(eventTypes, seed)
  const actor = event.type === 'worker_registered' || event.type === 'worker_verified' || event.type === 'account_suspended'
    ? pick(workers, seed * 3).name
    : pick(clients, seed * 2).name
  return {
    id: `EVT-${String(9000 + seed)}`,
    type: event.type,
    text: `${actor} ${event.label}`,
    time: minutesAgoLabel(seed * 27 + 4),
  }
})
