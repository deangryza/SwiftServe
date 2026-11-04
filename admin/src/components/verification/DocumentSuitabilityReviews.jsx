import { useEffect, useState, useRef } from 'react';
import { apiRequest, apiRequestBinary } from '../../lib/api';
import { useAdminAccess } from '../../lib/AdminAccessContext';
import { canReviewDocument, documentDecision } from '../../lib/documentReview';
import { createRequestGate } from '../../lib/requestGate';

export default function DocumentSuitabilityReviews() {
  const { can } = useAdminAccess();
  const [items, setItems] = useState([]), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState(null), [image, setImage] = useState(null), [reason, setReason] = useState('NOT_SUPPORTED');
  const [cursor,setCursor]=useState(null);
  const alive=useRef(true);
  const gate=useRef(null);
  if (!gate.current) gate.current=createRequestGate();
  useEffect(()=>{alive.current=true;return()=>{alive.current=false;};},[]);
  useEffect(() => () => { if (image) URL.revokeObjectURL(image); }, [image]);
  async function load(more=false) {
    if (!gate.current.tryStart()) return;
    setBusy(true); setError('');
    try { const result=await apiRequest(`/api/admin/document-reviews${more&&cursor ? `?after=${encodeURIComponent(cursor)}` : ''}`); setItems(previous=>more ? [...new Map([...previous,...result.items].map(item=>[item.ownerId,item])).values()] : result.items);setCursor(result.next); }
    catch { setError('Could not load document reviews. Check your access and refresh.'); }
    finally { gate.current.finish(); if (alive.current) setBusy(false); }
  }
  useEffect(() => { if (can('verification.view')) load(); }, []);
  async function open(item) {
    if (!gate.current.tryStart()) return;
    setSelected(item); setImage(null); setBusy(true); setError('');
    try {
      const blob = await apiRequestBinary(`/api/admin/document-reviews/${encodeURIComponent(item.ownerId)}/image?attemptId=${encodeURIComponent(item.attemptId)}`);
      if (!alive.current) return;
      setImage(URL.createObjectURL(blob));
    } catch { setError('Could not open this attempt. Refresh; a newer upload or expired image may exist.'); }
    finally { gate.current.finish(); if (alive.current) setBusy(false); }
  }
  async function decide(status, reasonCode) {
    if (!gate.current.tryStart()) return;
    setBusy(true); setError('');
    try {
      const { item } = await apiRequest(`/api/admin/document-reviews/${encodeURIComponent(selected.ownerId)}`, { method: 'PATCH', body: JSON.stringify(documentDecision(selected, status, reasonCode)) });
      setSelected(item); setItems(prev => prev.map(row => row.ownerId === item.ownerId ? item : row));
    } catch { setError('Decision rejected. Refresh the queue before retrying; permissions or the evidence attempt may have changed.'); }
    finally { gate.current.finish(); if (alive.current) setBusy(false); }
  }
  if (!can('verification.view')) return null;
  const reviewable = canReviewDocument(selected, can('verification.manage'));
  return <section className="mb-6 rounded-2xl border border-gray-200 bg-white p-4">
    <h2 className="text-lg font-semibold">Document suitability review</h2>
    <p className="text-sm text-gray-600">Manual appearance review only. This does not authenticate an ID, pass liveness or approve a worker.</p>
    <button disabled={busy} onClick={()=>load()} className="my-3 rounded-lg border px-4 py-2">{busy ? 'Loading…' : 'Refresh documents'}</button>
    {cursor && <button disabled={busy} onClick={()=>load(true)} className="m-3 rounded-lg border px-4 py-2">Load older documents</button>}
    {error && <p role="alert" className="text-red-700">{error}</p>}
    {!busy && !items.length && <p>No submitted documents.</p>}
    <p className="text-xs text-gray-500">100 submissions per page. Use Load older documents for earlier uploads.</p>
    <div className="max-h-64 overflow-y-auto">{items.map(item => <button key={item.ownerId} disabled={busy} onClick={() => open(item)} className="block w-full border-b p-3 text-left">
      {item.declaredType} · {item.ownerId} · {item.status}<br /><small>{String(item.submittedAt)} {item.mock ? 'MOCK / NOT OFFICIALLY VERIFIED' : ''}</small>
    </button>)}</div>
    {selected && <div className="mt-4 space-y-3">
      <h3 className="font-semibold">Declared type: {selected.declaredType} — {selected.status}</h3>
      {selected.mock && <p>MOCK / NOT OFFICIALLY VERIFIED — no official review allowed</p>}
      {image && <img src={image} alt="Private submitted document for this evidence attempt" className="max-h-96 max-w-full object-contain" />}
      <p>{selected.reason}</p>
      <label className="block">Replacement reason <select value={reason} onChange={e => setReason(e.target.value)} disabled={busy || !reviewable} className="ml-2 border p-2">
        <option value="NOT_SUPPORTED">Selfie, unrelated image or unsupported document</option><option value="INCOMPLETE">Document cropped or incomplete</option><option value="UNREADABLE">Document unreadable</option>
      </select></label>
      <div className="flex flex-wrap gap-2"><button disabled={busy || !reviewable || !image} onClick={() => decide('DOCUMENT_ACCEPTED','SUITABLE')} className="rounded-lg bg-yellow-400 px-4 py-2 disabled:opacity-50">Mark suitable for further verification</button>
        <button disabled={busy || !reviewable || !image} onClick={() => decide(reason === 'UNREADABLE' ? 'DOCUMENT_UNREADABLE' : 'DOCUMENT_REJECTED',reason)} className="rounded-lg border px-4 py-2 disabled:opacity-50">Reject and request replacement</button></div>
      <h4>Recent review history</h4><ul>{(selected.history || []).map((entry, i) => <li key={i}>{entry.status} · {entry.reasonCode} · {entry.reviewerId} · {String(entry.reviewedAt)} · Attempt {entry.attemptId}</li>)}</ul>
    </div>}
  </section>;
}
