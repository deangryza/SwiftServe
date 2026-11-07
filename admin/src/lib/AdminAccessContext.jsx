import { createContext, useContext, useEffect, useRef, useState } from 'react';
import { onIdTokenChanged } from 'firebase/auth';
import { auth } from './firebase';
import { apiRequest } from './api';
import { canOpen, canAccess, landingPage } from './adminAccess';

const Context = createContext(null);
export function AdminAccessProvider({ children }) {
  const [state, setState] = useState({ loading: true, access: null, catalog: {} });
  const generation = useRef(0);
  useEffect(() => {
    let disposed = false;
    const refresh = async () => {
      const version = ++generation.current;
      const user = auth.currentUser;
      if (!user) { setState({ loading: false, access: null, catalog: {} }); return; }
      setState(previous => ({ ...previous, loading: !previous.access || previous.access.uid !== user.uid }));
      try {
        const payload = await apiRequest('/api/admin/session');
        if (!disposed && version === generation.current && auth.currentUser?.uid === user.uid) setState({ loading: false, ...payload });
      } catch {
        if (!disposed && version === generation.current) setState({ loading: false, access: null, catalog: {} });
      }
    };
    const off = onIdTokenChanged(auth, refresh);
    const timer = setInterval(refresh, 30000);
    window.addEventListener('focus', refresh);
    return () => { disposed = true; generation.current++; off(); clearInterval(timer); window.removeEventListener('focus', refresh); };
  }, []);
  return <Context.Provider value={{ ...state, can: permission => canAccess(state.access, permission), canOpen: path => canOpen(state.access, path), landing: landingPage(state.access) }}>{children}</Context.Provider>;
}
export const useAdminAccess = () => useContext(Context);
