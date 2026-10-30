const { test } = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp } = require('firebase-admin/firestore');
const { eligibility, runExpiredJobCleanup, startExpiredJobCleanup, INTERVAL_MS } = require('../src/services/expiredJobCleanupService');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { ExpiredJobCheckpoint } = require('../src/services/expiredJobCheckpoint');
const { preflightEnvironment, preflightFirestore, assertDiskMount, runExpiredJobSweep,
  startExpiredJobWorker, verifyWorkerLock } = require('../src/services/expiredJobWorker');
const { launch } = require('../scripts/runExpiredJobCleanup');
const { main } = require('../scripts/expiredJobCleanupWorker');

const NOW = new Date('2026-10-29T04:00:00Z'); // Noon PHT.
const stamp = value => Timestamp.fromDate(new Date(value));
const expired = overrides => ({ status: 'pending', clientId: 'client',
  scheduleFrom: stamp('2026-10-29T01:00:00Z'), ...overrides });
const logger = () => {
  const entries = [];
  return { entries, info: value => entries.push(value), warn: value => entries.push(value), error: value => entries.push(value) };
};

// Small transactional fake: writes are applied only after a successful callback.
// Real concurrent client/server transactions are tested separately in the emulator.
class Database {
  constructor(records) { this.records = new Map(Object.entries(records)); this.beforeTransaction = null; this.failWrites = new Set(); this.failReads = new Set(); this.reads = []; }
  collection(path) { return new Query(this, path); }
  async runTransaction(callback) {
    if (this.beforeTransaction) { this.beforeTransaction(); this.beforeTransaction = null; }
    const writes = [];
    const result = await callback({ get: ref => { this.reads.push(ref.path); if (this.failReads.has(ref.path)) throw Object.assign(new Error('private read error'), { code: 14 }); return ref.get(); },
      update: (ref, data) => writes.push([ref.path, { ...this.records.get(ref.path), ...data }]),
      set: (ref, data) => writes.push([ref.path, data]) });
    if (writes.some(([path]) => this.failWrites.has(path))) throw Object.assign(new Error('private error payload'), { code: 14 });
    writes.forEach(([path, data]) => this.records.set(path, data));
    return result;
  }
}
class Reference {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split('/').at(-1); }
  collection(name) { return new Query(this.db, `${this.path}/${name}`); }
  async get() { return { id: this.id, ref: this, exists: this.db.records.has(this.path), data: () => this.db.records.get(this.path) }; }
}
class Query {
  constructor(db, path) { this.db = db; this.path = path; this.filters = []; this.maximum = Infinity; this.cursor = ''; }
  doc(id) { return new Reference(this.db, `${this.path}/${id}`); }
  where(field, operator, value) { assert.equal(operator, '=='); this.filters.push([field, value]); return this; }
  orderBy() { return this; }
  limit(maximum) { this.maximum = maximum; return this; }
  startAfter(cursor) { this.cursor = cursor; return this; }
  async get() {
    const matching = [...this.db.records].filter(([path, data]) => {
      const segments = path.split('/');
      return segments.slice(0, -1).join('/') === this.path && segments.at(-1) > this.cursor
        && this.filters.every(([field, value]) => data[field] === value);
    }).sort(([a], [b]) => a.localeCompare(b)).slice(0, this.maximum);
    const docs = await Promise.all(matching.map(([path]) => new Reference(this.db, path).get()));
    return { docs, size: docs.length, empty: !docs.length };
  }
}
const run = (db, options = {}) => runExpiredJobCleanup({ db, logger: logger(), dryRun: false, now: () => NOW, ...options });

test('expires only an eligible post, preserves history, and notifies exactly once', async () => {
  const db = new Database({ 'service_requests/old': expired(),
    'service_requests/old/private/location': { address: 'retained' },
    'notifications/n': { requestId: 'old' }, 'service_requests/other': expired({ status: 'completed' }) });
  const result = await run(db);
  assert.equal(result.expired, 1);
  assert.equal(result.expiredExamined, 1);
  assert.equal(db.records.get('service_requests/old').status, 'expired');
  const notification = db.records.get('notifications/jobExpired_old');
  assert.equal(notification.recipientId, 'client');
  assert.equal(notification.recipientRole, 'client');
  assert.equal(notification.requestId, 'old');
  assert.equal(notification.type, 'jobExpired');
  assert.equal(notification.read, false);
  assert.ok(notification.createdAt);
  assert.ok(db.records.get('service_requests/old').expiredAt);
  assert.ok(db.records.get('service_requests/old').scheduleFrom.isEqual(expired().scheduleFrom));
  assert.equal(db.records.has('service_requests/old/private/location'), true);
  assert.equal(db.records.has('notifications/n'), true);
  assert.equal(db.records.has('service_requests/other'), true);
  assert.equal((await run(db)).expired, 0);
});
test('future and exact-now times are retained', async () => {
  const db = new Database({ 'service_requests/future': expired({ scheduleFrom: stamp('2026-10-30T01:00:00Z') }),
    'service_requests/now': expired({ scheduleFrom: Timestamp.fromDate(NOW) }) });
  const result = await run(db);
  assert.equal(result.expired, 0);
  assert.equal(result.skipped.not_expired, 2);
});
for (const status of ['pending', 'accepted', 'rejected']) {
  test(`any ${status} application retains the request`, async () => {
    const db = new Database({ 'service_requests/old': expired(), 'service_requests/old/applications/worker': { status } });
    assert.equal((await run(db)).skipped.has_applications, 1);
    assert.equal(db.records.has('service_requests/old/applications/worker'), true);
  });
}
test('accepted ongoing completed cancelled and unknown statuses are ineligible', () => {
  for (const status of ['accepted', 'ongoing', 'completed', 'cancelled', 'booked', undefined]) {
    assert.equal(eligibility(expired({ status }), Timestamp.fromDate(NOW)), 'status_changed');
  }
});
test('assignment and transaction markers protect a pending record with inconsistent status', async () => {
  for (const field of ['workerId', 'workerName', 'acceptedAt', 'ongoingAt', 'completedAt', 'cancelledAt', 'errandStage', 'pickedUpAt', 'deliveringAt']) {
    const db = new Database({ 'service_requests/old': expired({ [field]: 'present' }) });
    assert.equal((await run(db)).skipped.assignment_or_transaction, 1);
  }
});
for (const name of ['conversations', 'reports', 'sos_alerts', 'reviews', 'client_reviews']) {
  test(`linked ${name} is preserved and retains the request`, async () => {
    const id = ['reviews', 'client_reviews'].includes(name) ? 'old' : 'history';
    const path = `${name}/${id}`;
    const db = new Database({ 'service_requests/old': expired(), [path]: { requestId: 'old' } });
    assert.equal((await run(db)).skipped[`linked_${name}`], 1);
    assert.equal(db.records.has(path), true);
  });
}
test('tracking records protect inconsistent pending bookings', async () => {
  const db = new Database({ 'service_requests/old': expired(), 'service_requests/old/private/rider_location': {} });
  assert.equal((await run(db)).skipped.tracking_record, 1);
});
test('missing malformed legacy and inconsistent schedule values are skipped and logged', async () => {
  const values = [expired({ scheduleFrom: undefined }), expired({ scheduleFrom: 'yesterday' }),
    expired({ scheduleFrom: undefined, schedule: stamp('2026-10-29T01:00:00Z') }),
    expired({ scheduleFrom: stamp('2026-10-28T16:00:00Z') }), // PHT midnight.
    expired({ scheduleTo: 'bad' }), expired({ scheduleTo: stamp('2026-10-28T01:00:00Z') }),
    expired({ schedule: stamp('2026-10-28T01:00:00Z') })];
  const db = new Database(Object.fromEntries(values.map((value, i) => [`service_requests/job${i}`, value])));
  const log = logger();
  const result = await run(db, { logger: log });
  assert.equal(result.expired, 0);
  assert.equal(Object.values(result.skipped).reduce((a, b) => a + b), values.length);
  assert.equal(log.entries.filter(entry => entry.event === 'expired_job_skipped').length, values.length);
});
test('latest applications and changed status are rechecked after candidate scan', async () => {
  const db = new Database({ 'service_requests/old': expired() });
  db.beforeTransaction = () => db.records.set('service_requests/old/applications/worker', { status: 'pending' });
  assert.equal((await run(db)).skipped.has_applications, 1);
  db.beforeTransaction = () => db.records.set('service_requests/old', expired({ status: 'accepted', workerId: 'worker' }));
  assert.equal((await run(db)).skipped.status_changed, 1);
});
test('a failed transaction stops before advancing its cursor and error payloads are not logged', async () => {
  const db = new Database({ 'service_requests/a': expired(), 'service_requests/b': expired() });
  db.failWrites.add('service_requests/a');
  const log = logger();
  const result = await run(db, { logger: log });
  assert.equal(result.errors, 1);
  assert.equal(result.expired, 0);
  assert.equal(result.status, 'failed');
  assert.equal(result.nextAfterId, null);
  assert.equal(db.records.get('service_requests/b').status, 'pending');
  assert.equal(db.records.has('service_requests/a'), true);
  assert.equal(JSON.stringify(log.entries).includes('private error payload'), false);
});
test('dry-run is the default and never writes', async () => {
  const db = new Database({ 'service_requests/old': expired() });
  const result = await runExpiredJobCleanup({ db, now: () => NOW, logger: logger() });
  assert.equal(result.wouldExpire, 1);
  assert.equal(db.records.get('service_requests/old').status, 'pending');
  assert.equal(db.records.has('notifications/jobExpired_old'), false);
  assert.equal(result.expired, 0);
  assert.equal(db.records.has('service_requests/old'), true);
});
test('bounded pagination continues through retained records and wraps at the end', async () => {
  const db = new Database(Object.fromEntries(['a', 'b', 'c', 'd', 'e'].map(id =>
    [`service_requests/${id}`, expired({ scheduleFrom: stamp('2026-11-01T01:00:00Z') })])));
  const first = await run(db, { maxPerRun: 3, pageSize: 2 });
  assert.equal(first.scanned, 3);
  assert.equal(first.nextAfterId, 'c');
  const second = await run(db, { maxPerRun: 3, pageSize: 2, startAfterId: first.nextAfterId });
  assert.equal(second.scanned, 2);
  assert.equal(second.nextAfterId, null);
});
test('scheduler defaults disabled and schedules nonoverlapping runs every 30 minutes', async () => {
  const timers = [];
  const setTimer = (fn, delay) => { timers.push({ fn, delay }); return timers.length; };
  startExpiredJobCleanup({ env: {}, db: {}, setTimer });
  assert.equal(timers.length, 0);
  let resolve;
  let calls = 0;
  const scheduler = startExpiredJobCleanup({ db: {}, env: { EXPIRED_JOB_CLEANUP_ENABLED: 'true' },
    logger: logger(), setTimer, clearTimer() {}, run: options => {
      calls++; assert.equal(options.dryRun, true);
      return new Promise(done => { resolve = done; });
    } });
  assert.equal(timers[0].delay, 0);
  const active = timers[0].fn();
  assert.equal(calls, 1);
  assert.equal(timers.length, 1);
  resolve({ nextAfterId: 'job' });
  await active;
  assert.equal(timers[1].delay, INTERVAL_MS);
  scheduler.stop();
});
test('scheduler stop during a run prevents rearming; failures are retried next interval', async () => {
  const timers = [];
  const log = logger();
  const scheduler = startExpiredJobCleanup({ db: {},
    env: { EXPIRED_JOB_CLEANUP_ENABLED: 'true', EXPIRED_JOB_CLEANUP_DRY_RUN: 'false' },
    logger: log, setTimer: fn => { timers.push(fn); return timers.length; }, clearTimer() {},
    run: async options => { assert.equal(options.dryRun, false); throw new Error('private'); } });
  await timers[0]();
  assert.equal(timers.length, 2);
  assert.equal(JSON.stringify(log.entries).includes('private'), false);
  scheduler.stop();
  await timers[1]();
  assert.equal(timers.length, 2);
});


test('notification failure rolls back expiration and retries safely', async () => {
  const db = new Database({ 'service_requests/old': expired() });
  db.failWrites.add('notifications/jobExpired_old');
  assert.equal((await run(db)).errors, 1);
  assert.equal(db.records.get('service_requests/old').status, 'pending');
  assert.equal(db.records.has('notifications/jobExpired_old'), false);
  db.failWrites.clear();
  assert.equal((await run(db)).expired, 1);
  assert.equal((await run(db)).expired, 0);
});

test('existing event read state survives retry and missing owners are skipped', async () => {
  const event = { read: true, createdAt: stamp('2026-10-28T01:00:00Z') };
  const db = new Database({ 'service_requests/old': expired(),
    'notifications/jobExpired_old': event, 'service_requests/bad': expired({ clientId: '' }) });
  const result = await run(db);
  assert.equal(result.expired, 1);
  assert.equal(result.skipped.missing_owner, 1);
  assert.deepEqual(db.records.get('notifications/jobExpired_old'), event);
});


test('representative activation dry run reports only eligible jobs and leaves every record unchanged', async () => {
  const db = new Database({
    'service_requests/expired': expired(),
    'service_requests/future': expired({ scheduleFrom: stamp('2026-10-30T01:00:00Z') }),
    'service_requests/applied': expired(),
    'service_requests/applied/applications/worker': { status: 'pending' },
    'service_requests/booked': expired({ status: 'accepted', workerId: 'worker' }),
    'service_requests/legacy': expired({ scheduleFrom: undefined, schedule: stamp('2026-10-29T01:00:00Z') }),
    'service_requests/midnight': expired({ scheduleFrom: stamp('2026-10-28T16:00:00Z') }),
    'service_requests/malformed': expired({ scheduleFrom: 'invalid' }),
    'service_requests/assigned-pending': expired({ workerId: 'worker' }),
    'service_requests/expired/private/location': { address: 'retained' },
    'notifications/existing': { read: true },
  });
  const before = new Map(db.records);
  const log = logger();
  const result = await run(db, { dryRun: true, logger: log });
  assert.equal(result.dryRun, true);
  assert.equal(result.scanned, 7); // Accepted booking is excluded by the pending query.
  assert.equal(result.wouldExpire, 1);
  assert.equal(result.expired, 0);
  assert.equal(result.errors, 0);
  assert.equal(result.skipped.not_expired, 1);
  assert.equal(result.skipped.has_applications, 1);
  assert.equal(result.skipped.assignment_or_transaction, 1);
  assert.equal(result.skipped.missing_or_invalid_start, 2);
  assert.equal(result.skipped.ambiguous_midnight, 1);
  assert.deepEqual(db.records, before);
  assert.deepEqual(log.entries.filter(entry => entry.event === 'expired_job_would_expire')
    .map(entry => entry.requestId), ['expired']);
});


// Production boot is tested only with injected SDK objects. No production
// configuration module, credential or RPC is used by these tests.
const workerEnv = () => ({ EXPIRED_JOB_CLEANUP_ENABLED: 'true',
  EXPIRED_JOB_CLEANUP_DRY_RUN: 'true', GOOGLE_CLOUD_PROJECT: 'swiftserve-production',
  EXPIRED_JOB_CLEANUP_DISK_MOUNT: '/var/data', EXPIRED_JOB_CLEANUP_STATE_DIR: '/var/data/expiry' });
const identity = { projectId: 'swiftserve-production', databaseId: '(default)', dryRun: true };
const memoryStore = () => ({ state: null, async load() { return this.state && structuredClone(this.state); },
  async save(value) { this.state = structuredClone(value); } });
async function fileStore(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'swiftserve-expiry-test-'));
  t.after(async () => {
    if (path.dirname(path.resolve(directory)) !== path.resolve(os.tmpdir()) ||
        !path.basename(directory).startsWith('swiftserve-expiry-test-')) throw new Error('Unsafe test cleanup path');
    await fs.rm(directory, { recursive: true, force: true });
  });
  return new ExpiredJobCheckpoint(directory, identity);
}
const pendingMany = count => Object.fromEntries(Array.from({ length: count }, (_, index) => [
  `service_requests/job${String(index).padStart(4, '0')}`,
  expired({ scheduleFrom: stamp('2026-11-01T01:00:00Z') }),
]));
const sweep = (db, store, options = {}) => runExpiredJobSweep({ db, store, logger: logger(), now: () => NOW, ...options });

test('disabled worker and launcher never initialize Firebase, touch disk, or spawn', async () => {
  const fail = () => { throw new Error('Must not run'); };
  await startExpiredJobWorker({ env: {}, logger: logger(), getDb: fail });
  assert.equal(await launch({ env: {}, logger: logger(), spawnChild: fail, filesystem: {} }), 0);
});
for (const [name, envChange, dbChange, code] of [
  ['wrong configured project', { GOOGLE_CLOUD_PROJECT: 'another-project' }, {}, 'WRONG_PROJECT'],
  ['conflicting project alias', { GCLOUD_PROJECT: 'another-project' }, {}, 'WRONG_PROJECT'],
  ['wrong resolved SDK project', {}, { projectId: 'another-project' }, 'WRONG_RESOLVED_PROJECT'],
  ['named database', {}, { databaseId: 'another-database' }, 'WRONG_DATABASE'],
  ['emulator host', { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8187' }, {}, 'PRODUCTION_EMULATOR_REJECTED'],
  ['empty emulator setting', { FIRESTORE_EMULATOR_HOST: '' }, {}, 'PRODUCTION_EMULATOR_REJECTED'],
  ['missing project', { GOOGLE_CLOUD_PROJECT: undefined }, {}, 'WRONG_PROJECT'],
  ['relative state path', { EXPIRED_JOB_CLEANUP_STATE_DIR: './state' }, {}, 'PERSISTENT_DISK_REQUIRED'],
  ['state outside disk', { EXPIRED_JOB_CLEANUP_STATE_DIR: '/tmp/expiry' }, {}, 'PERSISTENT_DISK_REQUIRED'],
  ['invalid mode', { EXPIRED_JOB_CLEANUP_DRY_RUN: 'FALSE' }, {}, 'INVALID_DRY_RUN_MODE'],
]) {
  test(`production preflight rejects ${name}`, () => {
    assert.throws(() => preflightFirestore({ ...identity, ...dbChange }, { ...workerEnv(), ...envChange }), { code });
  });
}
test('preflight accepts only the expected SDK project/default database; omitted dry-run is safe', () => {
  const env = workerEnv();
  delete env.EXPIRED_JOB_CLEANUP_DRY_RUN;
  assert.equal(preflightFirestore(identity, env).dryRun, true);
  assert.equal(preflightEnvironment({}).enabled, false);
});
test('mount validation rejects ephemeral/missing disks and accepts an explicit filesystem mount', () => {
  assertDiskMount('/var/data', '10 9 8:2 / /var/data rw - ext4 /dev/disk rw');
  for (const info of ['', '10 9 8:2 / /var/data rw - tmpfs tmpfs rw',
    '10 9 8:2 / /var/data rw - overlay overlay rw', '10 9 8:2 / / rw - ext4 /dev/disk rw']) {
    assert.throws(() => assertDiskMount('/var/data', info), { code: 'PERSISTENT_DISK_NOT_MOUNTED' });
  }
});
test('atomic disk checkpoint survives recreation and rejects corruption or mismatched identity', async t => {
  const store = await fileStore(t);
  assert.equal(await store.load(), null);
  const state = { sweepId: 'sweep', asOf: NOW.toISOString(), cursor: 'job1234', lastCompletedAt: null };
  await store.save(state);
  assert.equal((await new ExpiredJobCheckpoint(path.dirname(store.file), identity).load()).cursor, 'job1234');
  const otherProject = new ExpiredJobCheckpoint(path.dirname(store.file), { ...identity, projectId: 'another' });
  await assert.rejects(otherProject.load(), { code: 'CHECKPOINT_INVALID' });
  await fs.writeFile(store.file, '{broken');
  await assert.rejects(store.load(), { code: 'CHECKPOINT_INVALID' });
});
test('more than 1000 retained posts continue immediately and reach the late eligible post', async () => {
  const db = new Database(pendingMany(1205));
  db.records.set('service_requests/job1204', expired());
  const original = new Map(db.records);
  const store = memoryStore();
  const log = logger();
  const result = await sweep(db, store, { logger: log });
  assert.equal(result.status, 'complete');
  assert.equal(result.scanned, 1205);
  assert.equal(result.wouldExpire, 1);
  assert.equal(store.state.cursor, null);
  assert.equal(store.state.lastCompletedAt, NOW.toISOString());
  assert.equal(log.entries.filter(entry => entry.event === 'expired_job_sweep_complete').length, 1);
  assert.equal(log.entries.filter(entry => entry.event === 'expired_job_sweep_progress').length, 1);
  assert.deepEqual(db.records, original, 'Dry run must not write any Firestore document');
});
test('interruption checkpoints the last successful transaction and restart resumes later IDs', async t => {
  const db = new Database(pendingMany(1010));
  const store = await fileStore(t);
  let stopped = false;
  const save = store.save.bind(store);
  store.save = async state => { await save(state); if (state.cursor === 'job0003') stopped = true; };
  const firstLog = logger();
  assert.equal((await sweep(db, store, { shouldStop: () => stopped, logger: firstLog })).status, 'interrupted');
  assert.equal((await store.load()).cursor, 'job0003');
  assert.equal(firstLog.entries.some(entry => entry.event === 'expired_job_sweep_complete'), false);
  const restarted = new ExpiredJobCheckpoint(path.dirname(store.file), identity);
  const result = await sweep(db, restarted);
  assert.equal(result.scanned, 1006);
  assert.equal(result.status, 'complete');
  assert.equal(db.reads.filter(value => value === 'service_requests/job0003').length, 1);
});
test('partial read failure is a failed sweep and recovery retries the failed document', async () => {
  const db = new Database(pendingMany(4));
  const store = memoryStore();
  db.failReads.add('service_requests/job0001');
  const log = logger();
  await assert.rejects(sweep(db, store, { logger: log }), { code: 'CLEANUP_SWEEP_FAILED' });
  assert.equal(store.state.cursor, 'job0000');
  assert.equal(store.state.lastCompletedAt, null);
  assert.equal(log.entries.some(entry => entry.event === 'expired_job_sweep_complete'), false);
  db.failReads.clear();
  assert.equal((await sweep(db, store)).scanned, 3);
});
test('failed page query cannot become a successful complete sweep', async () => {
  const db = new Database(pendingMany(2));
  const original = db.collection.bind(db);
  db.collection = name => { const query = original(name); query.get = async () => { throw Object.assign(new Error('private'), { code: 7 }); }; return query; };
  const store = memoryStore();
  await assert.rejects(sweep(db, store), { code: 'CLEANUP_SWEEP_FAILED' });
  assert.equal(store.state.cursor, null);
  assert.equal(store.state.lastCompletedAt, null);
});
test('checkpoint failure never advances past the unpersisted cursor', async () => {
  const db = new Database(pendingMany(3));
  const store = memoryStore();
  const save = store.save.bind(store);
  store.save = async state => { if (state.cursor === 'job0001') throw Object.assign(new Error('disk full'), { code: 'ENOSPC' }); await save(state); };
  await assert.rejects(sweep(db, store), { code: 'CLEANUP_SWEEP_FAILED' });
  assert.equal(store.state.cursor, 'job0000');
  store.save = save;
  assert.equal((await sweep(db, store)).scanned, 2);
});
test('a batch without confirmed continuation fails instead of looping or claiming completion', async () => {
  await assert.rejects(sweep({}, memoryStore(), { runBatch: async () => ({ status: 'partial', scanned: 1000, nextAfterId: 'unpersisted' }) }), { code: 'CLEANUP_INCOMPLETE_SCAN' });
});
test('duplicate execution replay preserves the same notification and read state', async () => {
  const db = new Database({ 'service_requests/old': expired() });
  // Write-mode arguments affect only this in-memory fake; no process env changes.
  await sweep(db, memoryStore(), { dryRun: false });
  const event = db.records.get('notifications/jobExpired_old');
  event.read = true;
  await sweep(db, memoryStore(), { dryRun: false });
  assert.equal(db.records.get('notifications/jobExpired_old'), event);
  assert.equal(db.records.get('notifications/jobExpired_old').read, true);
  assert.equal([...db.records.keys()].filter(key => key.startsWith('notifications/')).length, 1);
});
test('shutdown waits for active transaction before closing Firestore and reporting stopped', async () => {
  let finish;
  const wait = new Promise(resolve => { finish = resolve; });
  let terminated = false;
  const db = { ...identity, async terminate() { terminated = true; } };
  const timers = [];
  const log = logger();
  const worker = await startExpiredJobWorker({ verifyLock: async () => {}, env: workerEnv(), getDb: () => db,
    createStore: memoryStore, logger: log, setTimer: fn => { timers.push(fn); return 1; }, clearTimer() {},
    runBatch: async options => { await wait; return { status: options.shouldStop() ? 'interrupted' : 'complete', scanned: 1 }; } });
  const tick = timers[0]();
  await new Promise(resolve => setImmediate(resolve));
  const stopped = worker.stop();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(terminated, false);
  assert.equal(log.entries.some(entry => entry.event === 'expired_job_worker_stopped'), false);
  finish();
  await stopped;
  await tick;
  assert.equal(terminated, true);
  assert.equal(timers.length, 1);
  assert.equal(log.entries.some(entry => entry.event === 'expired_job_sweep_complete'), false);
  assert.equal(log.entries.at(-1).event, 'expired_job_worker_stopped');
});
test('shutdown arriving during startup is drained after startup resolves', async () => {
  const signals = new EventEmitter();
  let finish;
  const start = new Promise(resolve => { finish = resolve; });
  let stops = 0;
  const boot = main({ start: () => start, signals, logger: logger() });
  signals.emit('SIGTERM');
  finish({ async stop() { stops++; } });
  await boot;
  assert.equal(stops, 1);
});
test('synchronous scan errors do not wedge the scheduler and stop remains drainable', async () => {
  const timers = [];
  const scheduler = startExpiredJobCleanup({ env: workerEnv(), db: {}, logger: logger(),
    setTimer: fn => { timers.push(fn); return 1; }, clearTimer() {}, run() { throw new Error('private'); } });
  await timers[0]();
  await timers[1]();
  await scheduler.stop();
  assert.equal(timers.length, 3);
});
test('launcher uses kernel flock, rejects duplicates and forwards shutdown signals', async () => {
  const signals = new EventEmitter();
  const child = new EventEmitter();
  const killed = [];
  child.kill = signal => killed.push(signal);
  let command, args;
  const log = logger();
  const running = launch({ env: workerEnv(), platform: 'linux', logger: log, signals,
    filesystem: { async readFile() { return '10 9 8:2 / /var/data rw - ext4 /dev/disk rw'; }, async mkdir() {}, async realpath(value) { return value; } },
    spawnChild: (name, values) => { command = name; args = values; return child; } });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(command, 'flock');
  assert.ok(args.includes('--no-fork'));
  assert.ok(args.includes('--nonblock'));
  signals.emit('SIGTERM');
  assert.deepEqual(killed, ['SIGTERM']);
  child.emit('exit', 73, null);
  assert.equal(await running, 73);
  assert.equal(log.entries.at(-1).event, 'expired_job_worker_already_running');
  assert.equal(signals.listenerCount('SIGTERM'), 0);
});


test('worker rejects bypassing launcher without acquiring the kernel lock', async () => {
  let initialized = false;
  await assert.rejects(startExpiredJobWorker({ env: workerEnv(), logger: logger(),
    verifyLock: async () => { throw Object.assign(new Error('lock missing'), { code: 'WORKER_KERNEL_LOCK_REQUIRED' }); },
    getDb: () => { initialized = true; return identity; },
  }), { code: 'WORKER_KERNEL_LOCK_REQUIRED' });
  assert.equal(initialized, false);
});
test('kernel lock verification requires the right file and current process write lock', async () => {
  let held = true;
  const filesystem = {
    async readFile(file) {
      if (file === '/proc/self/mountinfo') return '10 9 8:2 / /var/data rw - ext4 /dev/disk rw';
      return held ? 'lock: 1: FLOCK ADVISORY WRITE 1234 8:2:123 0 EOF' : 'pos: 0';
    },
    async realpath(value) { return value; }, async readdir() { return ['3']; },
    async readlink() { return '/var/data/expiry/worker.lock'; },
  };
  await verifyWorkerLock(preflightEnvironment(workerEnv()), filesystem, 1234);
  held = false;
  await assert.rejects(verifyWorkerLock(preflightEnvironment(workerEnv()), filesystem, 1234), { code: 'WORKER_KERNEL_LOCK_REQUIRED' });
});


test('commit followed by checkpoint failure safely replays without duplicate notification', async () => {
  const db = new Database({ 'service_requests/old': expired() });
  const store = memoryStore();
  const save = store.save.bind(store);
  store.save = async state => { if (state.cursor === 'old') throw Object.assign(new Error('disk'), { code: 'ENOSPC' }); await save(state); };
  await assert.rejects(sweep(db, store, { dryRun: false }), { code: 'CLEANUP_SWEEP_FAILED' });
  assert.equal(store.state.cursor, null);
  assert.equal(db.records.get('service_requests/old').status, 'expired');
  const event = db.records.get('notifications/jobExpired_old');
  event.read = true;
  store.save = save;
  assert.equal((await sweep(db, store, { dryRun: false })).status, 'complete');
  assert.equal(db.records.get('notifications/jobExpired_old'), event);
});


test('real installed Firestore SDK exposes the expected default-database identity without RPCs', async () => {
  const { Firestore } = require('@google-cloud/firestore');
  const db = new Firestore({ projectId: identity.projectId, databaseId: '(default)' });
  try { assert.equal(preflightFirestore(db, workerEnv()).dryRun, true); }
  finally { await db.terminate(); }
});
test('startup rejects resolved identity mismatch before creating a checkpoint or scheduling', async () => {
  let scheduled = false;
  await assert.rejects(startExpiredJobWorker({ env: workerEnv(), logger: logger(),
    verifyLock: async () => {}, getDb: () => ({ ...identity, databaseId: 'wrong' }),
    createStore: () => { throw new Error('Must not open checkpoint'); },
    setTimer() { scheduled = true; },
  }), { code: 'WRONG_DATABASE' });
  assert.equal(scheduled, false);
});
