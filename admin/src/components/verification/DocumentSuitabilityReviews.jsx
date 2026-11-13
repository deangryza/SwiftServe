import { useEffect, useState, useRef } from 'react';
import { ChevronRight, FileText, RefreshCw, X } from 'lucide-react';
import { apiRequest, apiRequestBinary } from '../../lib/api';
import { useAdminAccess } from '../../lib/AdminAccessContext';
import { canReviewDocument, documentDecision } from '../../lib/documentReview';
import { createRequestGate } from '../../lib/requestGate';

const STATUS = {
  DOCUMENT_REVIEW_REQUIRED: { label: 'Needs review', style: 'bg-amber-50 text-amber-700 border-amber-200' },
  DOCUMENT_ACCEPTED: { label: 'Accepted', style: 'bg-green-50 text-green-700 border-green-200' },
  DOCUMENT_REJECTED: { label: 'Rejected', style: 'bg-red-50 text-red-600 border-red-200' },
  DOCUMENT_UNREADABLE: { label: 'Unreadable', style: 'bg-gray-50 text-gray-600 border-gray-200' },
  DOCUMENT_PENDING: { label: 'Checking', style: 'bg-blue-50 text-blue-700 border-blue-200' },
};
const REASONS = { SUITABLE: 'Suitable', NOT_SUPPORTED: 'Unsupported image', INCOMPLETE: 'Cropped or incomplete', UNREADABLE: 'Unreadable' };

// Upload photos are deleted when their review window ends; the server then 404s.
const isExpired = item => Boolean(item?.expiresAt) && new Date(item.expiresAt) <= new Date();
const when = value => {
  const date = value ? new Date(value) : null;
  return date && !Number.isNaN(date.getTime())
    ? date.toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' })
    : '—';
};

function StatusPill({ item }) {
  const { label, style } = isExpired(item) && item.status !== 'DOCUMENT_ACCEPTED'
    ? { label: 'Expired', style: 'bg-gray-50 text-gray-500 border-gray-200' }
    : STATUS[item.status] || { label: item.status, style: 'bg-gray-50 text-gray-600 border-gray-200' };
  return <span className={`shrink-0 whitespace-nowrap rounded-full border px-2.5 py-1 text-xs font-medium ${style}`}>{label}</span>;
}

export default function DocumentSuitabilityReviews({ names = {} }) {
  const { can } = useAdminAccess();
  const [items, setItems] = useState([]), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const [selected, setSelected] = useState(null), [image, setImage] = useState(null), [imageError, setImageError] = useState('');
  const [reason, setReason] = useState('NOT_SUPPORTED'), [decisionError, setDecisionError] = useState('');
  const [filter, setFilter] = useState('review');
  const [cursor, setCursor] = useState(null);
  const alive = useRef(true);
  const gate = useRef(null);
  if (!gate.current) gate.current = createRequestGate();
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  useEffect(() => () => { if (image) URL.revokeObjectURL(image); }, [image]);

  async function load(more = false) {
    if (!gate.current.tryStart()) return;
    setBusy(true); setError('');
    try {
      const result = await apiRequest(`/api/admin/document-reviews${more && cursor ? `?after=${encodeURIComponent(cursor)}` : ''}`);
      setItems(previous => more ? [...new Map([...previous, ...result.items].map(item => [item.ownerId, item])).values()] : result.items);
      setCursor(result.next);
    } catch (e) {
      setError(e?.status ? `Could not load ID uploads: ${e.message}` : 'Could not load ID uploads. Check that the API is running, then refresh.');
    } finally { gate.current.finish(); if (alive.current) setBusy(false); }
  }
  useEffect(() => { if (can('verification.view')) load(); }, []);

  async function open(item) {
    setSelected(item); setImage(null); setImageError(''); setDecisionError('');
    if (isExpired(item)) { setImageError('This photo has expired and was removed from the server. The worker has to upload a new one.'); return; }
    if (!gate.current.tryStart()) return;
    setBusy(true);
    try {
      const blob = await apiRequestBinary(`/api/admin/document-reviews/${encodeURIComponent(item.ownerId)}/image?attemptId=${encodeURIComponent(item.attemptId)}`);
      if (alive.current) setImage(URL.createObjectURL(blob));
    } catch {
      setImageError('This photo is no longer available. The worker may have uploaded a newer one, so refresh the list.');
    } finally { gate.current.finish(); if (alive.current) setBusy(false); }
  }

  async function decide(status, reasonCode) {
    if (!gate.current.tryStart()) return;
    setBusy(true); setDecisionError('');
    try {
      const { item } = await apiRequest(`/api/admin/document-reviews/${encodeURIComponent(selected.ownerId)}`, { method: 'PATCH', body: JSON.stringify(documentDecision(selected, status, reasonCode)) });
      setSelected(item); setItems(prev => prev.map(row => row.ownerId === item.ownerId ? item : row));
    } catch {
      setDecisionError('The decision was not saved. Refresh the list and try again; the worker may have uploaded a newer photo.');
    } finally { gate.current.finish(); if (alive.current) setBusy(false); }
  }

  if (!can('verification.view')) return null;
  const needsReview = items.filter(item => item.status === 'DOCUMENT_REVIEW_REQUIRED' && !isExpired(item));
  const shown = filter === 'review' ? needsReview : items;
  const reviewable = canReviewDocument(selected, can('verification.manage')) && !isExpired(selected);
  const nameOf = item => names[item.ownerId] || 'Unknown worker';

  return <section className="mt-6 rounded-2xl border border-gray-100 bg-white shadow-sm">
    <div className="flex flex-wrap items-start justify-between gap-3 border-b border-gray-100 p-4 sm:p-5">
      <div>
        <h2 className="text-lg font-semibold text-gray-800">ID uploads</h2>
        <p className="mt-0.5 text-sm text-gray-500">ID photos are checked automatically. Only uploads marked <span className="font-medium text-amber-700">Needs review</span> need your decision.</p>
      </div>
      <button type="button" disabled={busy} onClick={() => load()} className="inline-flex items-center gap-2 rounded-xl border border-gray-200 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50">
        <RefreshCw size={14} className={busy ? 'animate-spin' : ''} /> Refresh
      </button>
    </div>

    <div className="flex gap-1 px-4 pt-3 sm:px-5" role="tablist">
      {[['review', `Needs review (${needsReview.length})`], ['all', `All uploads (${items.length})`]].map(([key, label]) =>
        <button key={key} type="button" role="tab" aria-selected={filter === key} onClick={() => setFilter(key)}
          className={`rounded-lg px-3 py-1.5 text-sm font-medium ${filter === key ? 'bg-blue-50 text-blue-700' : 'text-gray-500 hover:bg-gray-50'}`}>{label}</button>)}
    </div>

    {error && <p role="alert" className="mx-4 mt-3 rounded-xl bg-red-50 p-3 text-sm text-red-700 sm:mx-5">{error}</p>}

    <ul className="max-h-96 divide-y divide-gray-100 overflow-y-auto px-2 py-2 sm:px-3">
      {!busy && !shown.length && <li className="p-6 text-center text-sm text-gray-400">{filter === 'review' ? 'Nothing waiting for review.' : 'No ID uploads yet.'}</li>}
      {shown.map(item => <li key={item.ownerId}>
        <button type="button" onClick={() => open(item)} className="flex w-full items-center gap-3 rounded-xl p-3 text-left hover:bg-gray-50">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-gray-50 text-gray-500"><FileText size={16} /></span>
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-medium text-gray-800">{nameOf(item)}</span>
            <span className="block truncate text-xs text-gray-500">{item.declaredType} · {when(item.submittedAt)}{item.mock ? ' · Demo upload' : ''}</span>
          </span>
          <StatusPill item={item} />
          <ChevronRight size={16} className="shrink-0 text-gray-300" />
        </button>
      </li>)}
    </ul>
    {cursor && <div className="border-t border-gray-100 p-3 text-center">
      <button type="button" disabled={busy} onClick={() => load(true)} className="text-sm font-medium text-blue-600 hover:underline disabled:opacity-50">Load older uploads</button>
    </div>}

    {selected && <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4" onClick={() => setSelected(null)}>
      <div role="dialog" aria-modal="true" aria-label="ID upload review" className="max-h-[90vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white shadow-xl" onClick={e => e.stopPropagation()}>
        <div className="flex items-start justify-between gap-3 border-b border-gray-100 p-4">
          <div className="min-w-0">
            <p className="truncate font-semibold text-gray-800">{nameOf(selected)}</p>
            <p className="text-xs text-gray-500">{selected.declaredType} · uploaded {when(selected.submittedAt)}</p>
          </div>
          <div className="flex items-center gap-2"><StatusPill item={selected} />
            <button type="button" aria-label="Close" onClick={() => setSelected(null)} className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100"><X size={18} /></button></div>
        </div>
        <div className="space-y-4 p-4">
          <div className="flex min-h-48 items-center justify-center rounded-xl bg-gray-50">
            {image ? <img src={image} alt="Submitted ID photo" className="max-h-80 max-w-full rounded-lg object-contain" />
              : imageError ? <p className="p-6 text-center text-sm text-gray-500">{imageError}</p>
                : <p className="text-sm text-gray-400">Loading photo…</p>}
          </div>
          {selected.mock && <p className="rounded-xl bg-amber-50 p-3 text-sm text-amber-700">Demo upload: not an official document, so it cannot be reviewed.</p>}
          {selected.reason && <p className="text-sm text-gray-600">{selected.reason}</p>}
          {reviewable && <div className="space-y-3 rounded-xl border border-gray-100 p-3">
            <p className="text-sm font-medium text-gray-800">Your decision</p>
            <button type="button" disabled={busy || !image} onClick={() => decide('DOCUMENT_ACCEPTED', 'SUITABLE')} className="w-full rounded-xl bg-green-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50">Accept: the ID is clear and complete</button>
            <div className="flex flex-col gap-2 sm:flex-row">
              <select value={reason} onChange={e => setReason(e.target.value)} disabled={busy} className="min-w-0 flex-1 rounded-xl border border-gray-200 px-3 py-2 text-sm">
                <option value="NOT_SUPPORTED">Selfie, unrelated or unsupported image</option>
                <option value="INCOMPLETE">ID is cropped or incomplete</option>
                <option value="UNREADABLE">ID is unreadable</option>
              </select>
              <button type="button" disabled={busy || !image} onClick={() => decide(reason === 'UNREADABLE' ? 'DOCUMENT_UNREADABLE' : 'DOCUMENT_REJECTED', reason)} className="rounded-xl border border-red-200 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-50">Ask for a new photo</button>
            </div>
            <p className="text-xs text-gray-400">This only checks the photo. It does not approve the worker's account.</p>
          </div>}
          {decisionError && <p role="alert" className="text-sm text-red-600">{decisionError}</p>}
          {!!selected.history?.length && <div>
            <p className="mb-1 text-sm font-medium text-gray-800">History</p>
            <ul className="space-y-1 text-xs text-gray-500">{selected.history.map((entry, i) =>
              <li key={i}>{when(entry.reviewedAt)} · {STATUS[entry.status]?.label || entry.status}{entry.reasonCode ? ` (${REASONS[entry.reasonCode] || entry.reasonCode})` : ''}</li>)}</ul>
          </div>}
        </div>
      </div>
    </div>}
  </section>;
}
