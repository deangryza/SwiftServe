// src/data/dashboardStats.js
// Chart series and summary card definitions consumed by DashboardHome.

// 1. Monthly user registrations — bar chart (last 8 months)
export const monthlyRegistrations = [
  { month: 'Dec', users: 62 },
  { month: 'Jan', users: 78 },
  { month: 'Feb', users: 91 },
  { month: 'Mar', users: 84 },
  { month: 'Apr', users: 103 },
  { month: 'May', users: 118 },
  { month: 'Jun', users: 96 },
  { month: 'Jul', users: 74 },
]

// 3. Weekly bookings — line chart (last 7 days)
export const weeklyBookings = [
  { day: 'Mon', bookings: 14 },
  { day: 'Tue', bookings: 19 },
  { day: 'Wed', bookings: 16 },
  { day: 'Thu', bookings: 23 },
  { day: 'Fri', bookings: 27 },
  { day: 'Sat', bookings: 31 },
  { day: 'Sun', bookings: 21 },
]

// 4. Worker verification status — donut chart
export const verificationStatus = [
  { name: 'Verified', value: 64, color: '#12B76A' },
  { name: 'Pending', value: 11, color: '#F59E0B' },
  { name: 'Rejected', value: 5, color: '#F04438' },
]

// Summary / stat cards shown at the top of the dashboard
export const summaryStats = [
  { id: 'total-users', title: 'Total Users', value: '150', change: '+8.2%', trend: 'up', icon: 'Users', color: 'swift' },
  { id: 'verified-workers', title: 'Verified Workers', value: '64', change: '+5.1%', trend: 'up', icon: 'ShieldCheck', color: 'success' },
  { id: 'pending-verification', title: 'Pending Verification', value: '11', change: '-2.4%', trend: 'down', icon: 'Clock', color: 'warning' },
  { id: 'active-bookings', title: 'Active Bookings', value: '27', change: '+12.6%', trend: 'up', icon: 'CalendarClock', color: 'violet' },
  { id: 'completed-jobs', title: 'Completed Jobs', value: '918', change: '+9.3%', trend: 'up', icon: 'CheckCircle2', color: 'success' },
  { id: 'cancelled-jobs', title: 'Cancelled Jobs', value: '38', change: '-3.7%', trend: 'down', icon: 'XCircle', color: 'danger' },
  { id: 'reports-received', title: 'Reports Received', value: '20', change: '+1.9%', trend: 'up', icon: 'FileWarning', color: 'warning' },
  { id: 'resolved-complaints', title: 'Resolved Complaints', value: '4', change: '+4.4%', trend: 'up', icon: 'BadgeCheck', color: 'swift' },
]

// System health indicators
export const systemHealth = [
  { label: 'Server Status', value: 'Online', healthy: true, icon: 'Server' },
  { label: 'Online Users', value: '312', healthy: true, icon: 'Radio' },
  { label: 'Pending Reports', value: '9', healthy: true, icon: 'FileWarning' },
  { label: 'Pending Verification', value: '11', healthy: true, icon: 'ShieldQuestion' },
  { label: 'System Version', value: 'v2.4.1', healthy: true, icon: 'Tag' },
  { label: 'Database Status', value: 'Connected', healthy: true, icon: 'Database' },
  { label: 'API Status', value: 'Operational', healthy: true, icon: 'Plug' },
]

// Quick action shortcuts
export const quickActions = [
  { id: 'approve-workers', title: 'Approve Workers', description: 'Review pending ID and face verification', icon: 'UserCheck', color: 'success' },
  { id: 'manage-users', title: 'Manage Users', description: 'View, edit, or suspend client accounts', icon: 'Users', color: 'swift' },
  { id: 'view-reports', title: 'View Reports', description: 'Investigate open complaints and disputes', icon: 'FileWarning', color: 'warning' },
  { id: 'booking-requests', title: 'Booking Requests', description: 'Track ongoing and pending bookings', icon: 'CalendarClock', color: 'violet' },
  { id: 'analytics', title: 'Analytics', description: 'Explore platform performance trends', icon: 'BarChart3', color: 'swift' },
  { id: 'notifications', title: 'Notifications', description: 'Broadcast alerts to users and workers', icon: 'Bell', color: 'danger' },
]
