'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const { generate } = require('./corpus');
const { run } = require('./harness');

async function main(args) {
  if (args.length !== 1 || args[0] !== '--prepare') throw Error('Usage: node experiments/document-ocr/benchmark.js --prepare');
  // No path argument: external identity images cannot be submitted through CLI.
  const root = path.join(__dirname, `run-${new Date().toISOString().replace(/[:.]/g, '-')}`);
  await generate(root);
  const report = await run(root);
  await fs.writeFile(path.join(root, 'report.json'), JSON.stringify(report, null, 2), { flag: 'wx' });
  console.log(JSON.stringify({ directory: root, fixtures: report.sampleCount, ocrInferenceExecuted: false, metrics: 'NOT MEASURED' }, null, 2));
}
if (require.main === module) main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { main };
