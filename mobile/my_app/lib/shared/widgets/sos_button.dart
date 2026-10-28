import 'package:flutter/material.dart';

import '../config/emergency_config.dart';
import '../models/service_request.dart';
import '../services/api_service.dart';
import '../services/sos_service.dart';
import '../theme/app_theme.dart';

const sosRed = Color(0xFFD32F2F);

/// Red emergency button for an in-person job. Renders nothing when SOS does
/// not apply to [request].
class SosButton extends StatelessWidget {
  const SosButton({
    super.key,
    required this.request,
    this.service,
    this.compact = false,
  });

  final ServiceRequest request;
  final SosService? service;

  /// AppBar-sized pill instead of a full-width button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!sosAvailableFor(request)) return const SizedBox.shrink();
    void onPressed() => showSosFlow(context, request, service: service);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton.icon(
          key: const ValueKey('sos-button-compact'),
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: sosRed,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          icon: const Icon(Icons.sos_rounded, size: 20),
          label: const Text(
            'SOS',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('sos-button'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: sosRed,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.sos_rounded),
      label: const Text(
        'Emergency SOS',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }
}

/// Confirms once, then calls the emergency number right away and alerts
/// SwiftServe in the background. The other party is never notified.
Future<void> showSosFlow(
  BuildContext context,
  ServiceRequest request, {
  SosService? service,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.sos_rounded, color: sosRed, size: 48),
            const SizedBox(height: 8),
            const _DemoBadge(),
            const SizedBox(height: 12),
            const Text(
              'Call $emergencyLabel and alert SwiftServe?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Demo mode: your phone will dial the demo contact. '
              'SwiftServe safety will get your location, this booking and '
              'the other person\'s details. They will not be notified.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('sos-confirm'),
              onPressed: () => Navigator.pop(sheetContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: sosRed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(58),
              ),
              icon: const Icon(Icons.call_rounded),
              label: const Text(
                'Call $emergencyLabel now',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('sos-cancel'),
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final sos = service ?? SosService();
  // Start the alert first so it is underway while the dialer is open.
  final alert = sos.raiseAlert(request.id)..ignore();
  final dialed = await sos.callEmergency();
  if (!context.mounted) return;
  if (!dialed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sos.dialNumber.isEmpty
              ? 'Demo mode: no demo contact is set, so no call was made.'
              : 'Could not open the phone dialer.',
        ),
      ),
    );
  }
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SosActiveScreen(
        requestId: request.id,
        service: sos,
        initialAlert: alert,
      ),
    ),
  );
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      key: const ValueKey('sos-demo-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.softYellow,
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'DEMO MODE · calls the demo contact only',
        style: TextStyle(
          color: AppTheme.ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

enum _AlertState { sending, sent, failed }

class SosActiveScreen extends StatefulWidget {
  const SosActiveScreen({
    super.key,
    required this.requestId,
    required this.service,
    required this.initialAlert,
  });

  final String requestId;
  final SosService service;
  final Future<String> initialAlert;

  @override
  State<SosActiveScreen> createState() => _SosActiveScreenState();
}

class _SosActiveScreenState extends State<SosActiveScreen> {
  var _state = _AlertState.sending;
  String? _alertId;
  String? _error;
  var _markingSafe = false;

  @override
  void initState() {
    super.initState();
    _track(widget.initialAlert);
  }

  Future<void> _track(Future<String> alert) async {
    setState(() {
      _state = _AlertState.sending;
      _error = null;
    });
    try {
      final id = await alert;
      if (!mounted) return;
      setState(() {
        _alertId = id;
        _state = _AlertState.sent;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _AlertState.failed;
        _error = error is ApiException ? error.message : error.toString();
      });
    }
  }

  void _send() => _track(widget.service.raiseAlert(widget.requestId));

  Future<void> _markSafe() async {
    final id = _alertId;
    if (id == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _markingSafe = true);
    try {
      await widget.service.markSafe(id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _markingSafe = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.message : error.toString(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (_state) {
      _AlertState.sending => (
        Icons.cell_tower_rounded,
        'Alerting SwiftServe…',
        'Sending your location and booking details to the safety team.',
      ),
      _AlertState.sent => (
        Icons.verified_user_rounded,
        'SwiftServe has been alerted',
        'Our safety team has your location, this booking and the other '
            'person\'s details. Stay on the line with emergency services.',
      ),
      _AlertState.failed => (
        Icons.error_outline_rounded,
        'Couldn\'t alert SwiftServe',
        _error ?? 'Check your connection and retry. Calling still works.',
      ),
    };

    return Scaffold(
      backgroundColor: sosRed,
      appBar: AppBar(
        backgroundColor: sosRed,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Emergency SOS'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 32),
              children: [
                const _DemoBadge(),
                const SizedBox(height: 16),
                Icon(icon, color: Colors.white, size: 64),
                const SizedBox(height: 16),
                Text(
                  title,
                  key: const ValueKey('sos-status'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, height: 1.4),
                ),
                if (_state == _AlertState.sending) ...[
                  const SizedBox(height: 18),
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const ValueKey('sos-call-again'),
                  onPressed: widget.service.callEmergency,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: sosRed,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text(
                    'Call $emergencyLabel',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('sos-resend'),
                  onPressed: _state == _AlertState.sending ? null : _send,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: Icon(
                    _state == _AlertState.failed
                        ? Icons.refresh_rounded
                        : Icons.my_location_rounded,
                  ),
                  label: Text(
                    _state == _AlertState.failed
                        ? 'Retry alert'
                        : 'Update my location',
                  ),
                ),
                const SizedBox(height: 28),
                TextButton(
                  key: const ValueKey('sos-safe'),
                  onPressed: _markingSafe ? null : _markSafe,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.softYellow,
                  ),
                  child: Text(_markingSafe ? 'Updating…' : 'I\'m safe now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
