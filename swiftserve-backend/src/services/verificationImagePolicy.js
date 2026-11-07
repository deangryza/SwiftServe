const MAX_BYTES = 1536 * 1024;
const invalid = () => Object.assign(new Error('Use a valid JPEG or PNG, at most 1.5 MB and 2048 × 2048 pixels.'), { code: 'INVALID_VERIFICATION_IMAGE', status: 400 });
function inspectImage(file) {
  const b = file?.buffer;
  if (!Buffer.isBuffer(b) || b.length > MAX_BYTES || b.length < 24) throw invalid();
  let width, height;
  if (file.mimetype === 'image/png' && b.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) && b.toString('ascii', 12, 16) === 'IHDR' && b.readUInt32BE(8) === 13) {
    width = b.readUInt32BE(16); height = b.readUInt32BE(20);
  } else if (file.mimetype === 'image/jpeg' && b[0] === 255 && b[1] === 216) {
    let i = 2;
    while (i + 4 <= b.length) {
      if (b[i++] !== 255) throw invalid();
      while (b[i] === 255) i++;
      const marker = b[i++];
      if (marker === 218 || marker === 217) break;
      if (marker === 1 || (marker >= 208 && marker <= 215)) continue;
      if (i + 2 > b.length) throw invalid();
      const size = b.readUInt16BE(i);
      if (size < 2 || i + size > b.length) throw invalid();
      if ([192,193,194].includes(marker) && size >= 8) { height = b.readUInt16BE(i+3); width = b.readUInt16BE(i+5); break; }
      i += size;
    }
  }
  if (!width || !height || width < 16 || height < 16 || width > 2048 || height > 2048 || width * height > 4_000_000) throw invalid();
  return { width, height, bytes: b.length, contentType: file.mimetype };
}
module.exports = { MAX_BYTES, inspectImage };
