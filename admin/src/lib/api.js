import { auth } from './firebase';

const baseUrl = import.meta.env.VITE_API_BASE_URL || 'http://localhost:5000';

export async function apiRequest(path, options = {}) {
  const user = auth.currentUser;
  if (!user) throw new Error('Your admin session has expired.');
  const token = await user.getIdToken();
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      ...options.headers,
    },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || `Request failed (${response.status}).`);
  return payload;
}

// TODO(billing): fetches backend-served resources (local verification images)
// with the admin token, since plain links can't carry Authorization headers.
export async function apiRequestBinary(path) {
  const user = auth.currentUser;
  if (!user) throw new Error('Your admin session has expired.');
  const token = await user.getIdToken();
  const response = await fetch(`${baseUrl}${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`Request failed (${response.status}).`);
  return response.blob();
}
