// Local Windows/native/WASM measurements; never a claim of hosted compatibility.
Object.assign(process.env, require('./startNetlifyPilot').environment());
const { performance } = require('node:perf_hooks');
async function run() {
  const started = performance.now(), baseline = process.memoryUsage().rss;
  require('../src/app');
  console.log(JSON.stringify({ probe:'app-load', platform:process.platform,node:process.version,ms:Math.round(performance.now()-started),
    rssMiB:Math.round(process.memoryUsage().rss/1048576),deltaMiB:Math.round((process.memoryUsage().rss-baseline)/1048576),
    canvasLoaded:Object.keys(require.cache).some(key=>/node_modules[\\/]canvas[\\/]/.test(key)) }));
  const service = require('../src/services/faceVerificationService'), begin = performance.now();
  await service.loadModels();
  console.log(JSON.stringify({probe:'models',ms:Math.round(performance.now()-begin),rssMiB:Math.round(process.memoryUsage().rss/1048576)}));
  const image = require('canvas').createCanvas(64,64).toBuffer('image/png');
  try { await service.getFaceDescriptor(image,'selfie');throw new Error('Unexpected face in synthetic blank image'); }
  catch(error) {
    if(error.code!=='FACE_NOT_DETECTED')throw error;
    console.log(JSON.stringify({probe:'blank-inference',code:error.code,rssMiB:Math.round(process.memoryUsage().rss/1048576)}));
  }
}
run().catch(error=>{console.error('Local compatibility probe failed: '+String(error.code||error.message));process.exitCode=1;}).finally(async()=>{
  const {db}=require('../src/config/firebase');await db.terminate();await require('firebase-admin/app').deleteApp(require('firebase-admin/app').getApp());
});
