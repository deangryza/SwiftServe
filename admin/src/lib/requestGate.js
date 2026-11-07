// In-flight exclusion only: no response/evidence/token cache and no authorization.
export function createRequestGate() {
  let busy = false;
  return {
    tryStart() { if (busy) return false; busy = true; return true; },
    finish() { busy = false; },
  };
}
