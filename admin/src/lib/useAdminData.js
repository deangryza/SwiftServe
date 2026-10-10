import { useEffect, useState } from 'react';
import { apiRequest } from './api';

export default function useAdminData(resource, initialValue = []) {
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
    load();
    const interval = setInterval(load, 30000);
    return () => { active = false; clearInterval(interval); };
  }, [resource]);
  return { data, setData, loading, error };
}
