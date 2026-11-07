import 'package:flutter/material.dart';
import '../models/verification_evidence.dart';
import '../theme/app_theme.dart';

class VerificationEvidencePanel extends StatelessWidget {
  const VerificationEvidencePanel({
    super.key,
    required this.evidence,
    this.qr = 'DEMO NOT SCANNED',
  });
  final VerificationEvidence evidence;
  final String qr;
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppTheme.line),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Verification checks',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (evidence.mock)
            const Text(
              'MOCK / NOT OFFICIALLY VERIFIED',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          for (final row in <(String, String)>[
            ('Face matching', evidence.face),
            ('QR scan / format', qr),
            ('Government authentication', evidence.government),
            ('Server-side liveness', evidence.liveness),
            ('Administrative review', evidence.review),
            ('Worker eligibility', evidence.eligibility),
          ])
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.$1, style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    row.$2,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class DemoQrCheck extends StatefulWidget {
  const DemoQrCheck({super.key, required this.onResult});
  final ValueChanged<String> onResult;
  @override
  State<DemoQrCheck> createState() => _DemoQrCheckState();
}

class _DemoQrCheckState extends State<DemoQrCheck> {
  String _status = 'DEMO NOT SCANNED';
  bool _busy = false;
  Future<void> _scan(String payload) async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final status = DemoIdentityQr.valid(payload)
        ? 'DEMO QR FORMAT VALID'
        : 'DEMO QR FORMAT INVALID';
    setState(() {
      _status = status;
      _busy = false;
    });
    widget.onResult(status);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'QR scanning — DEMO',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Simulated scan of synthetic sample data. No camera decoding, real ID, PSA format or authenticity check. This result is not sent as verification evidence.',
          ),
          if (_busy) const LinearProgressIndicator(),
          Semantics(liveRegion: true, child: Text(_status)),
          OutlinedButton.icon(
            key: const ValueKey('demo-qr-valid'),
            onPressed: _busy ? null : () => _scan(DemoIdentityQr.sample),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Simulate sample scan — DEMO'),
          ),
          TextButton(
            key: const ValueKey('demo-qr-invalid'),
            onPressed: _busy ? null : () => _scan('INVALID-SYNTHETIC'),
            child: const Text('Try invalid sample — DEMO'),
          ),
        ],
      ),
    ),
  );
}
