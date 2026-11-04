// Internal SwiftServe contract ONLY. It is not a PSA request/response schema.
class IdentityProvider {
  async authenticate(_context) { throw new Error('Provider implementation required'); }
}
class MockPSAProvider extends IdentityProvider {
  constructor(scenario = 'manual_review') {
    super();
    if (!['success', 'failed', 'unavailable', 'expired', 'manual_review'].includes(scenario)) throw new Error('Unsupported mock scenario');
    this.scenario = scenario;
  }
  async authenticate() {
    if (this.scenario === 'unavailable') throw Object.assign(new Error('Mock provider unavailable'), { code: 'PROVIDER_UNAVAILABLE' });
    return { providerType: 'MOCK', outcome: {
      success: 'PASSED', failed: 'FAILED', expired: 'EXPIRED', manual_review: 'MANUAL_REVIEW',
    }[this.scenario] };
  }
}
module.exports = { IdentityProvider, MockPSAProvider };
