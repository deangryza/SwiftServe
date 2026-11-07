export const usesProtectedImages = backend => ['local', 'netlify-blobs'].includes(backend);
export function protectedImagePath(value) {
  const url = new URL(value, 'http://local.invalid');
  const path = url.pathname + url.search;
  if (!/^\/api\/admin\/verifications\/[^/]+\/image(?:\?kind=(?:selfie|document))?$/.test(path)) throw new Error('Invalid private verification image path.');
  return path;
}
