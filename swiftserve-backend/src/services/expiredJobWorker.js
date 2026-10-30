const path = require('node:path');
const { randomUUID } = require('node:crypto');
const fs = require('node:fs/promises');
const { runExpiredJobCleanup, startExpiredJobCleanup, safeCode } = require('./expiredJobCleanupService');
const { ExpiredJobCheckpoint } = require('./expiredJobCheckpoint');

const PROJECT = 'swiftserve-production';

function failure(code) { return Object.assign(new Error(code), { code }); }

function preflightEnvironment(env) {
  if (env.EXPIRED_JOB_CLEANUP_ENABLED !== 'true') return { enabled: false };
  if (env.EXPIRED_JOB_CLEANUP_DRY_RUN != null &&
      !['true', 'false'].includes(env.EXPIRED_JOB_CLEANUP_DRY_RUN)) throw failure('INVALID_DRY_RUN_MODE');
  if (env.FIRESTORE_EMULATOR_HOST !== undefined) throw failure('PRODUCTION_EMULATOR_REJECTED');
  if (env.GOOGLE_CLOUD_PROJECT !== PROJECT ||
      (env.GCLOUD_PROJECT && env.GCLOUD_PROJECT !== PROJECT)) throw failure('WRONG_PROJECT');
  const mount = env.EXPIRED_JOB_CLEANUP_DISK_MOUNT;
  const directory = env.EXPIRED_JOB_CLEANUP_STATE_DIR;
  if (!mount || !directory || !path.posix.isAbsolute(mount) || !path.posix.isAbsolute(directory) ||
      mount === '/' || path.posix.normalize(mount) !== mount ||
      path.posix.normalize(directory) !== directory || !directory.startsWith(`${mount}/`)) {
    throw failure('PERSISTENT_DISK_REQUIRED');
  }
  return { enabled: true, dryRun: env.EXPIRED_JOB_CLEANUP_DRY_RUN !== 'false', directory, mount };
}

function preflightFirestore(db, env) {
  const configuration = preflightEnvironment(env);
  if (!configuration.enabled) return configuration;
  // These are SDK configuration properties; no production RPC is made here.
  if (db.projectId !== PROJECT) throw failure('WRONG_RESOLVED_PROJECT');
  if (db.databaseId !== '(default)') throw failure('WRONG_DATABASE');
  return configuration;
}

function assertDiskMount(mount, mountInfo) {
  const mounted = mountInfo.split('\n').some(line => {
    const fields = line.split(' ');
    const point = fields[4]?.replace(/\\040/g, ' ').replace(/\\134/g, '\\');
    const type = line.split(' - ')[1]?.split(' ')[0];
    return point === mount && type && !['tmpfs', 'ramfs', 'overlay'].includes(type);
  });
  if (!mounted) throw failure('PERSISTENT_DISK_NOT_MOUNTED');
}

async function verifyWorkerLock(configuration, filesystem = fs, pid = process.pid) {
  assertDiskMount(configuration.mount, await filesystem.readFile('/proc/self/mountinfo', 'utf8'));
  const directory = await filesystem.realpath(configuration.directory);
  for (const fd of await filesystem.readdir('/proc/self/fd')) {
    try {
      if (await filesystem.readlink(`/proc/self/fd/${fd}`) !== `${directory}/worker.lock`) continue;
      const info = await filesystem.readFile(`/proc/self/fdinfo/${fd}`, 'utf8');
      if (new RegExp(`FLOCK\\s+ADVISORY\\s+WRITE\\s+${pid}\\s`).test(info)) return;
    } catch (error) {
      // /proc descriptors can disappear between listing and inspection.
      if (error.code !== 'ENOENT') throw error;
    }
  }
  throw failure('WORKER_KERNEL_LOCK_REQUIRED');
}

async function runExpiredJobSweep({ db, store, dryRun = true, logger = console,
  now = () => new Date(), shouldStop = () => false, runBatch = runExpiredJobCleanup }) {
  let state = await store.load();
  if (!state || state.sweepId === null) {
    state = { sweepId: randomUUID(), asOf: now().toISOString(), cursor: null,
      lastCompletedAt: state?.lastCompletedAt ?? null };
    await store.save(state);
  }
  logger.info({ event: 'expired_job_sweep_started', sweepId: state.sweepId,
    asOf: state.asOf, resumed: state.cursor !== null, dryRun });
  const summary = { status: 'interrupted', scanned: 0, expired: 0, wouldExpire: 0, errors: 0 };
  while (!shouldStop()) {
    const result = await runBatch({ db, dryRun, logger, shouldStop,
      now: () => new Date(state.asOf), startAfterId: state.cursor,
      onProgress: async cursor => {
        const next = { ...state, cursor };
        await store.save(next);
        state = next;
      } });
    for (const key of ['scanned', 'expired', 'wouldExpire', 'errors']) summary[key] += result[key] ?? 0;
    if (result.errors || result.status === 'failed') {
      logger.error({ event: 'expired_job_sweep_failed', sweepId: state.sweepId, ...summary, status: 'failed' });
      throw failure('CLEANUP_SWEEP_FAILED');
    }
    if (result.status === 'interrupted' || shouldStop()) break;
    if (result.status === 'complete') {
      await store.save({ sweepId: null, asOf: null, cursor: null, lastCompletedAt: now().toISOString() });
      logger.info({ event: 'expired_job_sweep_complete', sweepId: state.sweepId, ...summary, status: 'complete' });
      return { ...summary, status: 'complete', nextAfterId: null };
    }
    // Bound each batch, but immediately continue the sweep. Never claim that
    // 1,000 scanned documents means the entire pending queue was inspected.
    if (result.status !== 'partial' || !result.nextAfterId || result.nextAfterId !== state.cursor || !result.scanned) {
      throw failure('CLEANUP_INCOMPLETE_SCAN');
    }
    logger.info({ event: 'expired_job_sweep_progress', sweepId: state.sweepId,
      cursor: state.cursor, ...summary, status: 'partial' });
  }
  logger.warn({ event: 'expired_job_sweep_interrupted', sweepId: state.sweepId, ...summary });
  return { ...summary, nextAfterId: state.cursor };
}

async function startExpiredJobWorker({ env = process.env, logger = console,
  getDb = () => require('../config/firebase').db, createStore,
  setTimer, clearTimer, runBatch, now, verifyLock = verifyWorkerLock }) {
  const configuration = preflightEnvironment(env);
  if (!configuration.enabled) {
    logger.info({ event: 'expired_job_worker_disabled' });
    return { async stop() {} };
  }
  await verifyLock(configuration); // Internal entry point cannot bypass flock.
  const db = getDb();
  preflightFirestore(db, env);
  const identity = { projectId: PROJECT, databaseId: '(default)', dryRun: configuration.dryRun };
  const store = createStore ? createStore(identity) : new ExpiredJobCheckpoint(configuration.directory, identity);
  await store.load(); // Corrupt or mismatched progress prevents startup.
  logger.info({ event: 'expired_job_preflight_passed', ...identity });
  const scheduler = startExpiredJobCleanup({ db, env, logger, setTimer, clearTimer,
    run: options => runExpiredJobSweep({ ...options, store, runBatch, now }) });
  let closing;
  return { stop() {
    if (!closing) closing = (async () => {
      logger.info({ event: 'expired_job_shutdown_requested' });
      await scheduler.stop();
      await db.terminate();
      logger.info({ event: 'expired_job_worker_stopped' });
    })();
    return closing;
  } };
}

module.exports = { preflightEnvironment, preflightFirestore, assertDiskMount,
  verifyWorkerLock, runExpiredJobSweep, startExpiredJobWorker, safeCode };
