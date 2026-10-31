const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

// The entry point must hold the OS flock for this directory while using this
// store. No credentials, addresses or user data are stored here.
class ExpiredJobCheckpoint {
  constructor(directory, { projectId, databaseId, dryRun }) {
    this.identity = { version: 1, projectId, databaseId, dryRun };
    this.file = path.join(directory, dryRun ? 'checkpoint-dry-run.json' : 'checkpoint-expiration.json');
  }

  async load() {
    let data;
    try { data = JSON.parse(await fs.readFile(this.file, 'utf8')); }
    catch (error) {
      if (error.code === 'ENOENT') return null;
      throw Object.assign(new Error('Cannot read cleanup checkpoint.'), { code: 'CHECKPOINT_INVALID' });
    }
    const identityMatches = Object.entries(this.identity).every(([key, value]) => data?.[key] === value);
    const date = value => typeof value === 'string' && new Date(value).toISOString() === value;
    let valid = false;
    try {
      valid = identityMatches && (data.lastCompletedAt === null || date(data.lastCompletedAt)) &&
        (data.sweepId === null
          ? data.asOf === null && data.cursor === null
          : typeof data.sweepId === 'string' && data.sweepId.length > 0 && date(data.asOf) &&
            (data.cursor === null || (typeof data.cursor === 'string' && data.cursor.length > 0 &&
              Buffer.byteLength(data.cursor, 'utf8') <= 1500 && !data.cursor.includes('/'))));
    } catch { /* Invalid dates fail closed instead of silently discarding progress. */ }
    if (!valid) throw Object.assign(new Error('Cleanup checkpoint identity or state mismatch.'), { code: 'CHECKPOINT_INVALID' });
    return data;
  }

  async save(state) {
    const temporary = `${this.file}.${randomUUID()}.tmp`;
    let handle;
    try {
      handle = await fs.open(temporary, 'wx', 0o600);
      await handle.writeFile(JSON.stringify({ ...state, ...this.identity }) + '\n');
      await handle.sync();
      await handle.close();
      handle = null;
      await fs.rename(temporary, this.file);
      // Persist the rename as well as the file contents on the Linux host.
      if (process.platform !== 'win32') {
        const directory = await fs.open(path.dirname(this.file), 'r');
        try { await directory.sync(); } finally { await directory.close(); }
      }
    } finally {
      if (handle) await handle.close();
      await fs.unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
    }
  }
}

module.exports = { ExpiredJobCheckpoint };
