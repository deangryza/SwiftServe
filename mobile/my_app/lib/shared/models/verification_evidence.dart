/// Presentation only. These labels never grant worker authorization.
class VerificationEvidence {
  const VerificationEvidence({
    this.data = const {},
    this.requester = false,
    this.legacyAccess = false,
  });
  final Map<String, dynamic> data;
  final bool requester, legacyAccess;
  Map<String, dynamic> _map(String key) =>
      data[key] is Map ? Map<String, dynamic>.from(data[key]) : {};
  bool get mock =>
      data['providerType'] == 'MOCK' ||
      data['checkSource'] == 'SYNTHETIC_FIXTURE';
  String get face {
    final value = _map('face')['status'] ?? _map('faceResult')['status'];
    return switch (value ?? data['faceMatchBand'] ?? data['band']) {
      'MATCH' || 'strong' => 'FACE MATCHED',
      'BORDERLINE' || 'borderline' => 'BORDERLINE — RETAKE OR REVIEW',
      'NO_MATCH' || 'mismatch' => 'FACES DID NOT MATCH',
      'FACE_NOT_DETECTED' => 'FACE NOT DETECTED',
      'ERROR' => 'FACE CHECK ERROR',
      _ => 'FACE CHECK NOT STARTED',
    };
  }

  String get government {
    if (mock) return 'DEMO ONLY / NOT OFFICIALLY VERIFIED';
    if (_map('workerDecision')['officiallyVerified'] == true) {
      return 'GOVERNMENT AUTHENTICATION RECORDED';
    }
    return switch (_map('government')['status'] ?? data['governmentStatus']) {
      'NOT_AUTHENTICATED' => 'GOVERNMENT AUTHENTICATION FAILED',
      'EXPIRED' => 'GOVERNMENT EVIDENCE EXPIRED',
      'PENDING' => 'GOVERNMENT AUTHENTICATION PENDING',
      'ERROR' || 'UNAVAILABLE' => 'GOVERNMENT AUTHENTICATION UNAVAILABLE',
      _ => 'PSA NOT INTEGRATED / NOT OFFICIALLY VERIFIED',
    };
  }

  String get liveness =>
      switch (_map('liveness')['status'] ?? data['livenessStatus']) {
        'PASSED' => mock ? 'DEMO LIVENESS ONLY' : 'SERVER LIVENESS RECORDED',
        'FAILED' => 'SERVER LIVENESS FAILED',
        'EXPIRED' => 'SERVER LIVENESS EXPIRED',
        'PENDING' => 'SERVER LIVENESS PENDING',
        _ => 'LIVENESS NOT AVAILABLE',
      };
  String get review =>
      switch (_map('review')['status'] ?? data['reviewStatus']) {
        'APPROVED' => mock ? 'MOCK REVIEW APPROVED' : 'ADMIN REVIEW RECORDED',
        'REJECTED' => 'ADMIN REVIEW REJECTED',
        'NOT_REQUIRED' => 'NOT SUBMITTED FOR WORKER REVIEW',
        _ => 'ADMIN REVIEW PENDING',
      };
  String get eligibility => requester
      ? (mock
            ? 'MOCK RESULT — NO ACCOUNT APPROVAL'
            : legacyAccess || _map('workerDecision')['eligible'] == true
            ? 'ACCOUNT APPROVAL RECORDED'
            : 'ACCOUNT APPROVAL PENDING')
      : mock
      ? 'MOCK RESULT — NO WORKER PRIVILEGES'
      : legacyAccess && data['schemaVersion'] != 2
      ? 'EXISTING WORKER ACCESS — LEGACY STATUS'
      : _map('workerDecision')['eligible'] == true
      ? 'WORKER APPROVAL RECORDED'
      : 'WORKER APPROVAL PENDING / BLOCKED';
}

/// Internal synthetic format only; it is not a PhilSys/PSA QR specification.
abstract final class DemoIdentityQr {
  static const sample = 'SWIFTSERVE-DEMO:1:SYNTHETIC-001';
  static bool valid(String value) =>
      value.length <= 80 &&
      RegExp(r'^SWIFTSERVE-DEMO:1:SYNTHETIC-[0-9]{3}$').stringMatch(value) ==
          value;
}
