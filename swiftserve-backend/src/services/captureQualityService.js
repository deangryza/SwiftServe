// Capture usability only. Never authentication, liveness or authorization evidence.
const CAPTURE_QUALITY = Object.freeze({ minFaceSide: 64, sampleSide: 128, minMean: 15, maxMean: 240, minSharpness: 4 });
const GUIDANCE = Object.freeze({
  FACE_TOO_SMALL: 'Move closer so the face is larger and contains clear detail.',
  FACE_CROPPED: 'Keep the entire face inside the photo. Retake without cropping the face.',
  FACE_DETAIL: 'Keep your face fully visible and face the camera. For an ID, remove glare from the portrait.',
  TOO_DARK: 'Improve lighting and retake the photo. Avoid deep shadows on the face.',
  TOO_BRIGHT: 'Reduce bright light or glare on the face and retake the photo.',
  TOO_BLURRY: 'Hold the camera steady, focus on the face and retake the photo.',
});
class CaptureQualityError extends Error {
  constructor(reason, image) {
    super(GUIDANCE[reason]); this.name = 'CaptureQualityError';
    this.code = 'IMAGE_QUALITY'; this.reason = reason; this.image = image;
  }
}
function checkFaceGeometry(width, height, box, points, image) {
  const reject = reason => { throw new CaptureQualityError(reason, image); };
  if (![width, height, box?.x, box?.y, box?.width, box?.height].every(Number.isFinite)
    || width <= 0 || height <= 0 || box.width <= 0 || box.height <= 0) reject('FACE_DETAIL');
  if (box.x <= 0 || box.y <= 0 || box.x + box.width >= width || box.y + box.height >= height) reject('FACE_CROPPED');
  if (Math.min(box.width, box.height) < CAPTURE_QUALITY.minFaceSide) reject('FACE_TOO_SMALL');
  if (!Array.isArray(points) || points.length !== 68 || points.some(p => !Number.isFinite(p?.x) || !Number.isFinite(p?.y)
    || p.x <= 0 || p.y <= 0 || p.x >= width || p.y >= height)) reject('FACE_DETAIL');
}
function pixelMetrics(rgba, width, height) {
  const columns = Math.min(width, CAPTURE_QUALITY.sampleSide), rows = Math.min(height, CAPTURE_QUALITY.sampleSide);
  const gray = new Float64Array(columns * rows);
  let sum = 0;
  for (let y = 0; y < rows; y++) for (let x = 0; x < columns; x++) {
    const index = (Math.floor(y * (height - 1) / (rows - 1)) * width + Math.floor(x * (width - 1) / (columns - 1))) * 4;
    const value = 0.2126 * rgba[index] + 0.7152 * rgba[index + 1] + 0.0722 * rgba[index + 2];
    gray[y * columns + x] = value; sum += value;
  }
  let lapSum = 0, lapSquares = 0, count = 0;
  for (let y = 1; y < rows - 1; y++) for (let x = 1; x < columns - 1; x++) {
    const i = y * columns + x, lap = 4 * gray[i] - gray[i - 1] - gray[i + 1] - gray[i - columns] - gray[i + columns];
    lapSum += lap; lapSquares += lap * lap; count++;
  }
  return { mean: sum / gray.length, sharpness: lapSquares / count - (lapSum / count) ** 2 };
}
function checkPixelMetrics(metrics, image) {
  if (![metrics.mean, metrics.sharpness].every(Number.isFinite)) throw new CaptureQualityError('FACE_DETAIL', image);
  if (metrics.mean < CAPTURE_QUALITY.minMean) throw new CaptureQualityError('TOO_DARK', image);
  if (metrics.mean > CAPTURE_QUALITY.maxMean) throw new CaptureQualityError('TOO_BRIGHT', image);
  if (metrics.sharpness < CAPTURE_QUALITY.minSharpness) throw new CaptureQualityError('TOO_BLURRY', image);
}
function validateFaceCapture(canvas, result, image) {
  const box = result.detection.box;
  checkFaceGeometry(canvas.width, canvas.height, box, result.landmarks?.positions, image);
  // Read pixels only; never modify the recognition canvas, crop or descriptor.
  const pixels = canvas.getContext('2d').getImageData(Math.floor(box.x), Math.floor(box.y), Math.floor(box.width), Math.floor(box.height));
  checkPixelMetrics(pixelMetrics(pixels.data, pixels.width, pixels.height), image);
}
module.exports = { CAPTURE_QUALITY, CaptureQualityError, checkFaceGeometry, pixelMetrics, checkPixelMetrics, validateFaceCapture };
