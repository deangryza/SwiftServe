const path = require('node:path');
const fs = require('node:fs/promises');
const { spawn } = require('node:child_process');
const { preflightEnvironment, assertDiskMount, safeCode } = require('../src/services/expiredJobWorker');

async function launch({ env = process.env, logger = console, spawnChild = spawn,
  filesystem = fs, platform = process.platform, signals = process } = {}) {
  const configuration = preflightEnvironment(env);
  if (!configuration.enabled) {
    logger.info({ event: 'expired_job_worker_disabled' });
    return 0;
  }
  if (platform !== 'linux') throw Object.assign(new Error('Linux flock is required.'), { code: 'LINUX_WORKER_REQUIRED' });
  assertDiskMount(configuration.mount, await filesystem.readFile('/proc/self/mountinfo', 'utf8'));
  await filesystem.mkdir(configuration.directory, { recursive: true, mode: 0o700 });
  const actualMount = await filesystem.realpath(configuration.mount);
  const actualDirectory = await filesystem.realpath(configuration.directory);
  if (!actualDirectory.startsWith(`${actualMount}/`)) {
    throw Object.assign(new Error('State directory escapes its disk.'), { code: 'INVALID_STATE_DIRECTORY' });
  }
  // The kernel releases this lock on exit, including SIGKILL. Never remove a
  // stale lock file or steal a timed-out lease. --no-fork execs Node directly.
  const child = spawnChild('flock', ['--exclusive', '--nonblock', '--conflict-exit-code', '73',
    '--no-fork', path.join(actualDirectory, 'worker.lock'), process.execPath,
    '--use-system-ca', path.join(__dirname, 'expiredJobCleanupWorker.js')], { env, stdio: 'inherit' });
  const term = () => child.kill('SIGTERM');
  const interrupt = () => child.kill('SIGINT');
  signals.on('SIGTERM', term);
  signals.on('SIGINT', interrupt);
  try {
    return await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', (code, signal) => {
        if (code === 73) logger.error({ event: 'expired_job_worker_already_running' });
        if (signal) logger.error({ event: 'expired_job_worker_terminated', signal });
        resolve(code ?? 1);
      });
    });
  } finally {
    signals.removeListener('SIGTERM', term);
    signals.removeListener('SIGINT', interrupt);
  }
}

if (require.main === module) {
  require('dotenv').config({ quiet: true });
  launch().then(code => { process.exitCode = code; }).catch(error => {
    console.error({ event: 'expired_job_startup_failed', code: safeCode(error) });
    process.exitCode = 1;
  });
}

module.exports = { launch };
