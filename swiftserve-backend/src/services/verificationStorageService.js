const fs = require('fs/promises');
const path = require('path');

// TODO(billing): local-disk workaround so verification works without a Blaze
// plan / Cloud Storage bucket. Flip VERIFICATION_STORAGE=gcs (and set a real
// FIREBASE_STORAGE_BUCKET) to return to Cloud Storage. Local mode is for
// single-instance local demos only: files live on ephemeral disk and the admin
// panel loads them through an authenticated backend route, not signed URLs.
const LOCAL_BACKEND = 'local';
const GCS_BACKEND = 'gcs';

const storageMode = () => String(process.env.VERIFICATION_STORAGE || 'local').toLowerCase();
const isLocalStorage = (mode = storageMode()) => mode !== GCS_BACKEND;

const resolveUploadsDir = (uploadsDir = process.env.UPLOADS_DIR) => path.resolve(
  uploadsDir || path.join(__dirname, '../../uploads'),
);

// Guards against path traversal: every stored path must stay inside the
// uploads directory. Stored paths use posix separators for Firestore.
const toAbsolutePath = (relativePath, uploadsDir = resolveUploadsDir()) => {
  const base = path.resolve(uploadsDir);
  const absolute = path.resolve(base, ...String(relativePath || '').split('/'));
  if (absolute !== base && !absolute.startsWith(base + path.sep)) {
    throw new Error('Invalid storage path.');
  }
  return absolute;
};

const toStoredPath = (absolutePath, uploadsDir = resolveUploadsDir()) => path
  .relative(path.resolve(uploadsDir), absolutePath)
  .split(path.sep)
  .join('/');

const saveLocalBuffer = async (relativePath, buffer, uploadsDir = resolveUploadsDir()) => {
  const absolute = toAbsolutePath(relativePath, uploadsDir);
  await fs.mkdir(path.dirname(absolute), { recursive: true });
  await fs.writeFile(absolute, buffer);
  return toStoredPath(absolute, uploadsDir);
};

const removeLocalPaths = async (paths, uploadsDir = resolveUploadsDir()) => {
  await Promise.all(
    paths.filter(Boolean).map(async (relativePath) => {
      try {
        await fs.unlink(toAbsolutePath(relativePath, uploadsDir));
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
    }),
  );
};

const removeGcsPaths = async (bucket, paths) => {
  await Promise.allSettled(
    paths.filter(Boolean).map((filePath) => bucket.file(filePath).delete({ ignoreNotFound: true })),
  );
};

// Backend-aware removal for stored verification images. Local files are
// deleted; GCS objects use the non-throwing delete above.
const removeStoredFiles = async ({ paths, backend, storage, uploadsDir } = {}) => {
  const list = (paths || []).filter(Boolean);
  if (list.length === 0) return;
  if (backend === LOCAL_BACKEND) {
    await removeLocalPaths(list, uploadsDir);
    return;
  }
  await removeGcsPaths(storage.bucket(), list);
};

// Streams a locally stored verification image to an Express response.
// Returns true when a file was sent, false when there is nothing to serve.
const sendLocalFile = async (res, relativePath, { uploadsDir, contentType } = {}) => {
  let absolute;
  try {
    absolute = toAbsolutePath(relativePath, uploadsDir);
    await fs.access(absolute);
  } catch {
    return false;
  }
  res.setHeader('Content-Type', contentType || 'application/octet-stream');
  res.setHeader('Cache-Control', 'private, max-age=60');
  await new Promise((resolve, reject) => {
    res.sendFile(absolute, (error) => (error ? reject(error) : resolve()));
  });
  return true;
};

module.exports = {
  LOCAL_BACKEND,
  GCS_BACKEND,
  isLocalStorage,
  resolveUploadsDir,
  toAbsolutePath,
  saveLocalBuffer,
  removeLocalPaths,
  removeStoredFiles,
  sendLocalFile,
  storageMode,
};
