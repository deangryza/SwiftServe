const fs = require('fs/promises');
const path = require('path');

const MODEL_VERSION = '1.7.15';
const BASE_URL = `https://cdn.jsdelivr.net/npm/@vladmandic/face-api@${MODEL_VERSION}/model`;
const MODELS_PATH = path.resolve(__dirname, '../models');
const MODEL_FILES = [
  'ssd_mobilenetv1_model-weights_manifest.json',
  'ssd_mobilenetv1_model.bin',
  'face_landmark_68_model-weights_manifest.json',
  'face_landmark_68_model.bin',
  'face_recognition_model-weights_manifest.json',
  'face_recognition_model.bin',
];

const force = process.argv.includes('--force');

const isCompleteFile = async (filePath) => {
  try {
    const stats = await fs.stat(filePath);
    return stats.isFile() && stats.size > 0;
  } catch {
    return false;
  }
};

const download = async (filename) => {
  const destination = path.join(MODELS_PATH, filename);
  if (!force && await isCompleteFile(destination)) {
    console.log(`Using existing ${filename}`);
    return;
  }

  const temporary = `${destination}.tmp-${process.pid}`;
  try {
    const response = await fetch(`${BASE_URL}/${filename}`);
    if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText}`);
    const content = Buffer.from(await response.arrayBuffer());
    if (content.length === 0) throw new Error('download was empty');
    await fs.writeFile(temporary, content, { flag: 'wx' });
    if (force) await fs.rm(destination, { force: true });
    await fs.rename(temporary, destination);
    console.log(`Downloaded ${filename}`);
  } catch (error) {
    await fs.rm(temporary, { force: true });
    throw new Error(`Could not download ${filename}: ${error.message}`);
  }
};

const main = async () => {
  await fs.mkdir(MODELS_PATH, { recursive: true });
  for (const filename of MODEL_FILES) await download(filename);
  console.log(`Face models are ready in ${MODELS_PATH}`);
};

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
