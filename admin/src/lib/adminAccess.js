export const MODULES = {
  '/dashboard': ['dashboard.view', 'analytics.view'],
  '/dashboard/users': ['users.view', 'workers.view', 'clients.view'],
  '/dashboard/verification': ['verification.view'],
  '/dashboard/bookings': ['bookings.view'], '/dashboard/reports': ['reports.view'],
  '/dashboard/categories': ['categories.view'], '/dashboard/sos': ['sos.view'],
};
export function canAccess(access, permission) {
  return access?.fullAccess === true || access?.permissions?.includes(permission) === true;
}
export function canOpen(access, path) {
  if (!access) return false;
  if (path === '/dashboard/profile') return true;
  if (path === '/dashboard/administrators') return access.isSuperAdmin === true;
  return MODULES[path]?.some(permission => canAccess(access, permission)) === true;
}
export function landingPage(access) {
  return Object.keys(MODULES).find(path => canOpen(access, path)) || '/dashboard/profile';
}
