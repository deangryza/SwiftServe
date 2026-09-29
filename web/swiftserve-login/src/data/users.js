// src/data/users.js
// 150 static users (80 workers + 70 clients) with realistic Filipino names & locations.
// Generated once and consumed by tables, stat cards, and charts across the dashboard.

const metroManilaAreas = [
  'Quezon City', 'Makati', 'Taguig', 'Pasig', 'Mandaluyong', 'Manila',
  'Paranaque', 'Las Pinas', 'Muntinlupa', 'Caloocan', 'Marikina', 'Pasay',
]

const provinces = [
  'Cebu City', 'Davao City', 'Angeles City', 'Bacolod City', 'Iloilo City',
  'Cagayan de Oro', 'Baguio City', 'Batangas City',
]

const firstNames = [
  'Juan', 'Maria', 'Jose', 'Ana', 'Pedro', 'Rosa', 'Carlos', 'Luz',
  'Antonio', 'Carmen', 'Miguel', 'Teresa', 'Ramon', 'Cristina', 'Eduardo',
  'Josefina', 'Ricardo', 'Angelica', 'Fernando', 'Beatriz', 'Manuel', 'Divina',
  'Roberto', 'Grace', 'Andres', 'Marites', 'Danilo', 'Precious', 'Arnel', 'Jenny',
]

const lastNames = [
  'Santos', 'Reyes', 'Cruz', 'Bautista', 'Ocampo', 'Garcia', 'Mendoza',
  'Torres', 'Ramos', 'Flores', 'Villanueva', 'Castillo', 'Del Rosario',
  'Aquino', 'Gonzales', 'Fernandez', 'Salazar', 'Pascual', 'Domingo', 'Navarro',
]

function pick(arr, seed) {
  return arr[seed % arr.length]
}

function buildName(seed) {
  return `${pick(firstNames, seed)} ${pick(lastNames, seed * 7 + 3)}`
}

function buildLocation(seed) {
  const pool = seed % 3 === 0 ? provinces : metroManilaAreas
  return pick(pool, seed * 5 + 1)
}

export const workerCategories = [
  'Plumbing', 'Electrical', 'Aircon Repair', 'House Cleaning', 'Carpentry',
  'Appliance Repair', 'Painting', 'Pest Control', 'Massage Therapy', 'Gardening',
  'Car Wash', 'Laundry Service',
]

// 80 workers
export const workers = Array.from({ length: 80 }, (_, i) => {
  const seed = i + 1
  const verified = seed % 5 !== 0 // ~80% verified
  return {
    id: `WRK-${String(1000 + seed)}`,
    name: buildName(seed),
    category: pick(workerCategories, seed),
    location: buildLocation(seed),
    rating: (3.6 + ((seed * 37) % 14) / 10).toFixed(1),
    jobsCompleted: 5 + ((seed * 13) % 240),
    status: verified ? 'Verified' : (seed % 5 === 1 ? 'Pending' : 'Rejected'),
    joinDate: `2025-${String(1 + (seed % 12)).padStart(2, '0')}-${String(1 + (seed % 27)).padStart(2, '0')}`,
    idSubmitted: seed % 5 !== 2,
    faceVerified: verified,
  }
})

// 70 clients
export const clients = Array.from({ length: 70 }, (_, i) => {
  const seed = i + 101
  return {
    id: `CLI-${String(2000 + seed)}`,
    name: buildName(seed),
    location: buildLocation(seed),
    joinDate: `2025-${String(1 + (seed % 12)).padStart(2, '0')}-${String(1 + (seed % 27)).padStart(2, '0')}`,
    bookingsMade: 1 + (seed % 18),
    status: seed % 11 === 0 ? 'Suspended' : 'Active',
  }
})

// 150 combined users for aggregate stats
export const allUsers = [...workers, ...clients]

export const pendingWorkers = workers.filter((w) => w.status === 'Pending').slice(0, 8)
