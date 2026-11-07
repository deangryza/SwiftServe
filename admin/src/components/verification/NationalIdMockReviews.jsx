import { useEffect, useState } from 'react';
import { useAdminAccess } from '../../lib/AdminAccessContext';
import { apiRequest } from '../../lib/api';
import { canApproveMock, mockReviewRecord, MOCK_IDENTITY_LABEL } from '../../lib/nationalIdMockReview';

export default function NationalIdMockReviews() {
  const { access, can } = useAdminAccess();
  const enabled = import.meta.env.DEV && import.meta.env.VITE_ENABLE_NATIONAL_ID_MOCK === 'true';
  const view = enabled && can('verification.view'), manage = view && can('verification.manage');
  const [items, setItems] = useState([]), [revision, setRevision] = useState(0);
  const [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const [reasons, setReasons] = useState({});
  const [after, setAfter] = useState(''), [nextCursor, setNextCursor] = useState(null);
  useEffect(() => {
    let active = true;
    setItems([]); setError('');
    if (view) {
      setBusy(true);
      apiRequest(`/api/admin/identity/sessions${after ? `?after=${encodeURIComponent(after)}` : ''}`).then(result => {
        if (active) { setItems((result.items || []).filter(mockReviewRecord)); setNextCursor(result.nextCursor || null); }
      }).catch(() => { if (active) setError('Local mock reviews could not be loaded.'); })
        .finally(() => { if (active) setBusy(false); });
    }
    return () => { active = false; };
  }, [view, access?.uid, revision, after]);
  if (!view) return null;
  async function decide(item, decision) {
    if (!manage || !reasons[item.verificationReference]) return;
    setBusy(true); setError('');
    try {
      await apiRequest(`/api/admin/identity/sessions/${item.verificationReference}`, {
        method: 'PATCH', body: JSON.stringify({ decision, reasonCode: reasons[item.verificationReference] }),
      });
      setRevision(value => value + 1);
    } catch { setError('Review refused. Required checks, permissions, session expiry, or ownership may have changed.'); }
    finally { setBusy(false); }
  }
  return <section className="mb-6 rounded-2xl border border-amber-200 bg-white p-5" aria-label="National ID mock review">
    <h2 className="font-semibold text-gray-900">National ID mock review</h2>
    <p className="mt-2 text-sm font-semibold text-amber-800">{MOCK_IDENTITY_LABEL}</p>
    <p className="mt-2 text-sm text-gray-600">Synthetic records only. No images or ID numbers are retained. These decisions do not grant account verification or worker access. Missing face or server liveness evidence prevents approval.</p>
    <button className="mt-3 rounded-lg border px-4 py-2" disabled={busy} onClick={() => { setAfter(''); setRevision(value => value + 1); }}>Refresh mock reviews</button>
    {nextCursor && <button className="ml-2 mt-3 rounded-lg border px-4 py-2" disabled={busy} onClick={() => setAfter(nextCursor)}>Next review batch</button>}
    {error && <p role="alert" className="mt-2 text-red-700">{error}</p>}
    {!busy && !items.length && <p className="mt-3 text-sm text-gray-600">No pending mock reviews in this batch (maximum 25).</p>}
    {items.map(item => <article key={item.verificationReference} className="mt-4 rounded-xl border p-4">
      <p className="break-all text-sm">Account: {item.userId} · {item.accountType}</p>
      <p className="text-sm">{item.verificationStatus} · Mock government: {item.governmentVerificationStatus} · Face: {item.faceVerificationStatus} · Liveness: {item.livenessStatus}</p>
      {manage && <div className="mt-3 flex flex-wrap gap-2">
        <select aria-label={`Reason for ${item.userId}`} disabled={busy} className="rounded-lg border p-2" value={reasons[item.verificationReference] || ''} onChange={event => setReasons(previous => ({ ...previous, [item.verificationReference]: event.target.value }))}>
          <option value="">Select review reason</option>
          <option value="CHECKS_REVIEWED">Checks reviewed (mock only)</option>
          <option value="INCONSISTENT_EVIDENCE">Inconsistent evidence</option>
          <option value="UNSUPPORTED_CHECKS">Required checks unsupported</option>
        </select>
        <button className="rounded-lg bg-amber-300 px-4 py-2 text-gray-900 disabled:opacity-50" disabled={busy || !canApproveMock(item) || !reasons[item.verificationReference]} onClick={() => decide(item, 'approve')}>Approve mock result</button>
        <button className="rounded-lg border px-4 py-2 disabled:opacity-50" disabled={busy || !reasons[item.verificationReference]} onClick={() => decide(item, 'reject')}>Reject mock result</button>
      </div>}
    </article>)}
  </section>;
}
