// Internal entry point: use npm run jobs:cleanup, which obtains the kernel lock.
const { startExpiredJobWorker, safeCode } = require('../src/services/expiredJobWorker');

async function main({ start = startExpiredJobWorker, signals = process, logger = console } = {}) {
  let worker;
  let stopping = false;
  let drain;
  function stop() {
    stopping = true;
    if (worker && !drain) drain = worker.stop().catch(error => {
      logger.error({ event: 'expired_job_shutdown_failed', code: safeCode(error) });
      signals.exitCode = 1;
    });
    return drain;
  }
  signals.on('SIGINT', stop);
  signals.on('SIGTERM', stop);
  try {
    worker = await start();
    if (stopping) await stop();
    return worker;
  } catch (error) {
    signals.removeListener('SIGINT', stop);
    signals.removeListener('SIGTERM', stop);
    throw error;
  }
}

if (require.main === module) {
  main().catch(error => {
    console.error({ event: 'expired_job_startup_failed', code: safeCode(error) });
    process.exitCode = 1;
  });
}

module.exports = { main };
