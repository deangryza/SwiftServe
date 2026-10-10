import { onAuthStateChanged } from 'firebase/auth';
import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';

import { auth } from '../lib/firebase';

export default function ProtectedRoute({ children }) {
  const [state, setState] = useState({ loading: true, authorized: false });

  useEffect(() => onAuthStateChanged(auth, async (user) => {
    if (!user) {
      setState({ loading: false, authorized: false });
      return;
    }
    try {
      const token = await user.getIdTokenResult(true);
      setState({ loading: false, authorized: token.claims.admin === true });
    } catch { setState({ loading: false, authorized: false }); }
  }), []);

  if (state.loading) {
    return <div className="min-h-screen grid place-items-center text-slate-500">Checking admin access…</div>;
  }
  return state.authorized ? children : <Navigate to="/" replace />;
}
