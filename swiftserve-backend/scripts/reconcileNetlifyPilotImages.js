// Manual, emulator-only reconciliation. Not a deployed/scheduled function.
if (!process.env.PILOT_ADMIN_TOKEN) throw new Error('PILOT_ADMIN_TOKEN from local Auth emulator is required.');
fetch('http://localhost:8888/api/pilot/verification-images/reconcile', { method: 'POST', redirect: 'error',
  headers: { Authorization: `Bearer ${process.env.PILOT_ADMIN_TOKEN}` } }).then(async response => {
  console.log(JSON.stringify(await response.json())); process.exitCode = response.ok ? 0 : 1;
}).catch(() => { console.error('Local pilot cleanup request failed. No cloud fallback.'); process.exitCode = 1; });
