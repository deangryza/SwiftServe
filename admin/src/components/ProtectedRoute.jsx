import { Navigate } from 'react-router-dom';
import { useAdminAccess } from '../lib/AdminAccessContext';

export default function ProtectedRoute({ children, module }) {
  const state = useAdminAccess();
  if (state.loading) {
    return <div className="min-h-screen grid place-items-center text-slate-500">Checking admin access…</div>;
  }
  if (!state.access) return <Navigate to="/" replace />;
  if (module && !state.canOpen(module)) return <Navigate to={state.landing} replace />;
  return children;
}
