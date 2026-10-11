const { loadImage, createCanvas } = require('canvas');

const normalizeProfilePhoto = async (value) => {
  if (typeof value !== 'string' || value.length === 0 || value.length > 65536
      || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new Error('Choose a JPEG or PNG profile photo smaller than 48 KB.');
  }
  const bytes = Buffer.from(value, 'base64');
  const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const png = bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  if ((!jpeg && !png) || bytes.toString('base64') !== value || bytes.length > 49152) {
    throw new Error('Choose a JPEG or PNG profile photo smaller than 48 KB.');
  }
  if (png && (bytes.length < 24 || bytes.readUInt32BE(16) > 512 || bytes.readUInt32BE(20) > 512)) {
    throw new Error('Profile photos must be resized before uploading.');
  }
  const image = await loadImage(bytes);
  if (image.width > 512 || image.height > 512) {
    throw new Error('Profile photos must be resized before uploading.');
  }
  const scale = Math.min(1, 256 / Math.max(image.width, image.height));
  const canvas = createCanvas(Math.max(1, Math.round(image.width * scale)), Math.max(1, Math.round(image.height * scale)));
  const context = canvas.getContext('2d');
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas.toBuffer('image/jpeg', { quality: 0.7 }).toString('base64');
};

module.exports = { normalizeProfilePhoto };
