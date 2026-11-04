import { useCallback, useEffect, useState } from 'react';
import { Plus, RefreshCw, ShieldCheck } from 'lucide-react';
import { apiRequest } from '../../lib/api';
import { useAdminAccess } from '../../lib/AdminAccessContext';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

const empty = { fullName: '', email: '', password: '', role: 'Administrator', permissions: [], status: 'active' };
const date = value => value ? new Date(value).toLocaleString() : 'Not available';
const selectStyle = 'min-h-10 rounded-lg border border-slate-300 bg-white px-3 text-sm focus-visible:outline-2 focus-visible:outline-primary-600';

export default function AdminManagement() {
  const { access, catalog } = useAdminAccess();
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [role, setRole] = useState('all');
  const [editor, setEditor] = useState(null);
  const [form, setForm] = useState(empty);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');
  const [activity, setActivity] = useState(null);
  const load = useCallback(async () => {
    setLoading(true); setError('');
    try { setItems((await apiRequest('/api/admin/administrators')).items); }
    catch (error) { setError(error.message); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { load(); }, [load]);
  useEffect(() => { if (editor) document.getElementById('admin-editor-name')?.focus(); }, [editor]);
  function open(item) {
    setForm(item ? { ...item, password: '' } : { ...empty, permissions: [] });
    setEditor(item || 'new'); setFormError(''); setNotice('');
  }
  const change = key => event => setForm(value => ({ ...value, [key]: event.target.value }));
  async function save(event) {
    event.preventDefault();
    if (editor !== 'new' && form.status !== editor.status && form.status !== 'active' &&
      !window.confirm(`${form.status === 'suspended' ? 'Suspend' : 'Deactivate'} ${form.fullName}? They will lose administrator access.`)) return;
    setSaving(true); setFormError('');
    const body = { fullName: form.fullName, email: form.email, role: form.role, permissions: form.permissions,
      ...(editor === 'new' ? { password: form.password } : { status: form.status, version: editor.version }) };
    try {
      await apiRequest('/api/admin/administrators' + (editor === 'new' ? '' : '/' + encodeURIComponent(editor.id)), {
        method: editor === 'new' ? 'POST' : 'PATCH', body: JSON.stringify(body),
      });
      setForm(empty); setEditor(null); setNotice('Administrator saved. Permissions take effect on the next API request.');
      await load();
    } catch (error) { setFormError(error.message); }
    finally { setSaving(false); }
  }
  async function viewActivity(item) {
    setActivity({ name: item?.fullName || 'All administrators', loading: true, items: [] });
    try {
      const result = await apiRequest('/api/admin/administrators/audit' + (item ? '?actorId=' + encodeURIComponent(item.id) : ''));
      setActivity({ name: item?.fullName || 'All administrators', loading: false, items: result.items });
    } catch (error) { setActivity({ name: item?.fullName || 'All administrators', loading: false, error: error.message, items: [] }); }
  }
  async function retrySetup(item) {
    if (!window.confirm(`Retry administrator setup for ${item.fullName}?`)) return;
    try {
      await apiRequest('/api/admin/administrators/' + encodeURIComponent(item.id) + '/complete-setup', { method: 'POST' });
      await load();
    } catch (error) { setError(error.message); }
  }
  const filtered = items.filter(item => `${item.fullName} ${item.email} ${item.role}`.toLowerCase().includes(search.toLowerCase()) &&
    (status === 'all' || item.status === status) && (role === 'all' || item.role === role));
  return <div className="space-y-6">
    <header className="flex flex-wrap items-start justify-between gap-4">
      <div><p className="text-sm font-medium text-primary-700">Super Admin workspace</p><h1 className="mt-1 text-2xl font-semibold text-slate-950">Admin Management</h1><p className="mt-1 text-sm text-slate-500">Manage administrator access without changing your Super Admin account.</p></div>
      <div className="flex flex-wrap gap-2"><Button variant="outline" onClick={load} disabled={loading}><RefreshCw aria-hidden="true" />Refresh</Button><Button onClick={() => open(null)}><Plus aria-hidden="true" />Create Admin</Button></div>
    </header>
    {error && <p role="alert" className="rounded-xl bg-danger-50 p-4 text-sm text-danger-600">{error}</p>}
    {notice && <p role="status" className="rounded-xl bg-success-50 p-4 text-sm text-success-600">{notice}</p>}
    {editor && <Card><CardHeader><CardTitle>{editor === 'new' ? 'Create administrator' : 'Edit administrator'}</CardTitle></CardHeader><CardContent>
      <form onSubmit={save} className="space-y-5" aria-label="Administrator information">
        {formError && <p role="alert" className="text-sm text-danger-600">{formError}</p>}
        <div className="grid gap-4 sm:grid-cols-2">
          <label className="space-y-2 text-sm font-medium">Full name<Input id="admin-editor-name" value={form.fullName} onChange={change('fullName')} required maxLength={120} autoComplete="name" /></label>
          <label className="space-y-2 text-sm font-medium">Email address<Input type="email" value={form.email} onChange={change('email')} required maxLength={254} autoComplete="email" /></label>
          <label className="space-y-2 text-sm font-medium">Admin role<Input value={form.role} onChange={change('role')} required maxLength={60} /><span className="block text-xs font-normal text-slate-500">A label such as Support or Reviewer. Permissions control access.</span></label>
          {editor === 'new' ? <label className="space-y-2 text-sm font-medium">Temporary password<Input type="password" value={form.password} onChange={change('password')} required minLength={12} maxLength={128} autoComplete="new-password" /><span className="block text-xs font-normal text-slate-500">Use uppercase, lowercase, a number and a symbol. Share privately; it is never saved in Firestore.</span></label>
            : <label className="flex flex-col gap-2 text-sm font-medium">Account status<select className={selectStyle} value={form.status} onChange={change('status')}><option value="active">Active / restored</option><option value="inactive">Deactivated</option><option value="suspended">Suspended</option></select></label>}
        </div>
        <fieldset className="rounded-xl border border-slate-200 p-4"><legend className="px-2 text-sm font-semibold">Assigned permissions</legend><p className="mb-3 text-xs text-slate-500">Manage/edit access also grants the corresponding view access. Admin Management stays exclusive to the Super Admin.</p><div className="grid gap-1 sm:grid-cols-2 lg:grid-cols-3">{Object.entries(catalog).map(([key, label]) => <label key={key} className="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg p-2 text-sm hover:bg-slate-50"><input type="checkbox" className="size-4 accent-primary-600" checked={form.permissions.includes(key)} onChange={event => setForm(value => ({ ...value, permissions: event.target.checked ? [...value.permissions, key] : value.permissions.filter(item => item !== key) }))} />{label}</label>)}</div></fieldset>
        <div className="flex gap-2"><Button type="submit" disabled={saving}>{saving ? 'Saving…' : 'Save administrator'}</Button><Button type="button" variant="outline" disabled={saving} onClick={() => { setForm(empty); setEditor(null); }}>Cancel</Button></div>
      </form>
    </CardContent></Card>}
    <Card><CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><CardTitle>Administrators <span className="text-sm font-normal text-slate-500">({items.length})</span></CardTitle><Button variant="outline" onClick={() => viewActivity(null)}>View activity log</Button></div></CardHeader><CardContent className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto_auto]"><label className="space-y-1 text-xs font-medium text-slate-600">Search administrators<Input placeholder="Name, email or role" value={search} onChange={event => setSearch(event.target.value)} /></label><label className="flex flex-col gap-1 text-xs font-medium text-slate-600">Role<select className={selectStyle} value={role} onChange={event => setRole(event.target.value)}><option value="all">All roles</option>{[...new Set(items.map(item => item.role))].map(role => <option key={role}>{role}</option>)}</select></label><label className="flex flex-col gap-1 text-xs font-medium text-slate-600">Status<select className={selectStyle} value={status} onChange={event => setStatus(event.target.value)}><option value="all">All statuses</option>{['active', 'inactive', 'suspended', 'provisioning', 'updating'].map(status => <option key={status}>{status}</option>)}</select></label></div>
      <Table><TableHeader><TableRow><TableHead>Administrator</TableHead><TableHead>Role</TableHead><TableHead>Status</TableHead><TableHead>Created</TableHead><TableHead>Last login</TableHead><TableHead>Actions</TableHead></TableRow></TableHeader><TableBody>
        {loading && <TableRow><TableCell colSpan={6} role="status">Loading administrators…</TableCell></TableRow>}
        {!loading && !filtered.length && <TableRow><TableCell colSpan={6} className="py-8 text-center text-slate-500">No administrators match these filters.</TableCell></TableRow>}
        {filtered.map(item => <TableRow key={item.id}><TableCell><p className="font-medium">{item.fullName || 'Administrator'}</p><p className="text-xs text-slate-500">{item.email}</p></TableCell><TableCell>{item.role}{item.isSuperAdmin && <ShieldCheck size={16} aria-label="Protected Super Admin" className="ml-1 inline text-primary-600" />}</TableCell><TableCell><span className={`rounded-full px-2 py-1 text-xs font-medium ${item.status === 'active' && !item.authDisabled ? 'bg-success-50 text-success-600' : 'bg-warning-50 text-warning-600'}`}>{item.status}</span>{(item.syncRequired || (item.status === 'active' && item.authDisabled)) && <p className="mt-1 text-xs text-warning-600">Synchronization required</p>}</TableCell><TableCell className="text-xs">{date(item.createdAt)}</TableCell><TableCell className="text-xs">{date(item.lastLogin)}</TableCell><TableCell><div className="flex flex-wrap gap-2">{item.status === 'provisioning' ? <Button size="sm" variant="outline" onClick={() => retrySetup(item)}>Retry setup</Button> : item.managed && !item.isSuperAdmin && item.id !== access.uid ? <Button size="sm" variant="outline" onClick={() => open(item)}>Edit access</Button> : <span className="self-center text-xs text-slate-500">Protected account</span>}<Button size="sm" variant="ghost" onClick={() => viewActivity(item)}>Activity</Button></div></TableCell></TableRow>)}
      </TableBody></Table>
    </CardContent></Card>
    {activity && <Card><CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><CardTitle>Activity — {activity.name}</CardTitle><Button variant="ghost" onClick={() => setActivity(null)}>Close activity</Button></div></CardHeader><CardContent>{activity.error && <p role="alert" className="text-danger-600">{activity.error}</p>}<p className="mb-3 text-xs text-slate-500">Most recent 100 actions. Audit history is read-only.</p>{activity.loading ? <p role="status">Loading activity…</p> : <ul className="divide-y divide-slate-100">{activity.items.map(item => <li key={item.id} className="py-3 text-sm"><p className="font-medium">{item.action}</p><p className="break-words text-slate-500">{item.actorName} · {item.targetId} · {date(item.createdAt)}</p></li>)}{!activity.items.length && !activity.error && <li className="py-3 text-sm text-slate-500">No recorded actions yet.</li>}</ul>}</CardContent></Card>}
  </div>;
}
