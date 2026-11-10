import { useEffect, useState } from 'react';
import { apiRequest } from './api';

export default function useAdminData(resource, initialValue = [], pollMs = 300000) {
  const [data, setData] = useState(initialValue);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    async function load() {
      try {
        const payload = await apiRequest(`/api/admin/${resource}`);
        if (active) { setData(payload.items ?? payload.item ?? payload); setError(''); }
      } catch (failure) { if (active) setError(failure.message); }
      finally { if (active) setLoading(false); }
    }
    // Hidden tabs do not refresh, and catch up as soon as they are shown again.
    const refreshIfVisible = () => { if (document.visibilityState === 'visible') load(); };
    load();
    const interval = setInterval(refreshIfVisible, pollMs);
    document.addEventListener('visibilitychange', refreshIfVisible);
    return () => {
      active = false;
      clearInterval(interval);
      document.removeEventListener('visibilitychange', refreshIfVisible);
    };
  }, [resource, pollMs]);
  return { data, setData, loading, error };
}
