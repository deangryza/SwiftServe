import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'activity_push_router.dart';
import '../widgets/push_permission_explanation.dart';
import '../repositories/profile_repository.dart';
import '../models/service_request.dart';
import '../screens/reviews_screen.dart';
import '../utils/role_context.dart';
import '../../features/client/presentation/screens/client_sections.dart';
import '../../features/client/presentation/screens/client_notifications_screen.dart';
import '../../features/worker/presentation/screens/worker_job_details_screen.dart';
import '../../features/worker/presentation/screens/worker_verification_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/client/presentation/screens/client_request_details_screen.dart';

import '../../firebase_options.dart';
import 'expiry_push_router.dart';
export 'expiry_push_router.dart';

@pragma('vm:entry-point')
Future<void> expiryBackgroundMessage(RemoteMessage message) async {
  // OS displays notification payloads. Never create a second local notification,
  // perform expiration, write tokens or navigate from a background isolate.
  if (!ExpiryPushService.enabled) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

/// No FCM, token registration, permission prompt or callable request when disabled.
class ExpiryPushService with WidgetsBindingObserver {
  ExpiryPushService._();
  static final instance = ExpiryPushService._();
  static const enabled =
      bool.fromEnvironment('ENABLE_PUSH_NOTIFICATIONS') ||
      bool.fromEnvironment('ENABLE_EXPIRY_PUSH');
  static final navigatorKey = GlobalKey<NavigatorState>();
  String? _readyUid;
  String? _token;
  String? _installation;
  int _generation = 0;
  Future<void> _registration = Future.value();
  bool _initialized = false;
  bool _prompting = false;
  final Set<String> _foregroundEvents = {};
  late final _activityRouter = ActivityPushRouter(
    load: (collection, id) async =>
        (await FirebaseFirestore.instance.collection(collection).doc(id).get())
            .data(),
    navigate: _openActivity,
    onError: _openError,
  );
  void _openError() {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open this update. Try Notifications when connected.',
          ),
        ),
      );
    }
  }

  Future<void> _openActivity(
    String type,
    String id,
    Map<String, dynamic> data,
  ) async {
    final uid = _readyUid;
    final generation = _generation;
    if (uid == null) return;
    Widget destination;
    if (type == 'chatMessage') {
      final participants = List<String>.from(data['participantIds']);
      final other = participants.firstWhere((value) => value != uid);
      final public =
          (await FirebaseFirestore.instance
                  .collection('public_profiles')
                  .doc(other)
                  .get())
              .data();
      destination = ClientChatScreen(
        conversationId: id,
        otherPersonName: public?['fullName'] as String? ?? 'Conversation',
      );
    } else {
      final profile = await ProfileRepository().watch(uid).first;
      if (profile == null) return;
      if (isVerificationNotification(data)) {
        destination = WorkerVerificationScreen(profile: profile);
      } else if (data['type'] == 'reviewReceived') {
        destination = ReviewsScreen(
          userId: uid,
          reviewsFor: ReviewsFor.account,
        );
      } else {
        final requestId = data['requestId'];
        if (requestId is! String || !validPushDocumentId(requestId)) return;
        final document = await FirebaseFirestore.instance
            .collection('service_requests')
            .doc(requestId)
            .get();
        if (!document.exists) return;
        final request = ServiceRequest.fromDocument(document);
        if (request.clientId == uid) {
          destination = clientNotificationDestination(
            data['type'] as String?,
            request,
          );
        } else {
          destination = WorkerJobDetailsScreen(
            request: request,
            worker: profile,
          );
        }
      }
      // Navigation does not depend on an optional read-state write succeeding.
      try {
        await FirebaseFirestore.instance
            .collection('notifications')
            .doc(id)
            .update({'read': true});
      } catch (_) {}
    }
    if (generation != _generation || _readyUid != uid) return;
    await navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  Future<Map<String, bool>> preferences() async {
    const defaults = {'enabled': false, 'chats': true, 'activities': true};
    if (!enabled) return Map.of(defaults);
    final uid = _readyUid;
    if (uid == null) return Map.of(defaults);
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final entry in defaults.entries)
        entry.key: prefs.getBool('push.$uid.${entry.key}') ?? entry.value,
    };
  }

  Future<void> openSystemSettings() async {
    try {
      await const MethodChannel(
        'swiftserve/notification_settings',
      ).invokeMethod<void>('open');
    } catch (_) {}
  }

  Future<void> updatePreferences(
    BuildContext context,
    Map<String, bool> values,
  ) async {
    if (!_initialized || _readyUid == null) return;
    final uid = _readyUid!;
    final generation = _generation;
    var selected = Map<String, bool>.of(values);
    if (selected['enabled'] == true &&
        (await preferences())['enabled'] != true) {
      if (!context.mounted) return;
      selected['enabled'] = await requestPushConsent(
        context,
        requestPermission: () async {
          final permission = await FirebaseMessaging.instance
              .requestPermission();
          return [
            AuthorizationStatus.authorized,
            AuthorizationStatus.provisional,
          ].contains(permission.authorizationStatus);
        },
      );
    }
    final status = await FirebaseMessaging.instance.getNotificationSettings();
    if (![
      AuthorizationStatus.authorized,
      AuthorizationStatus.provisional,
    ].contains(status.authorizationStatus)) {
      selected['enabled'] = false;
    }
    if (_readyUid != uid) return;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in selected.entries) {
      await prefs.setBool('push.$uid.${entry.key}', entry.value);
    }
    if (_readyUid != uid || _generation != generation) return;
    if (_token != null) await _register(_token!);
    if (selected['enabled'] != true) {
      await FirebaseMessaging.instance.deleteToken();
      _token = null;
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } else {
      await _activate(uid);
    }
  }

  Future<void> _explainOnce(String uid) async {
    if (_prompting) return;
    _prompting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('push.$uid.explained') == true || _readyUid != uid) {
        return;
      }
      await prefs.setBool('push.$uid.explained', true);
      final choices = await preferences();
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted || _readyUid != uid) return;
      await updatePreferences(context, {...choices, 'enabled': true});
    } catch (_) {
      /* Optional permission must not interrupt onboarding. */
    } finally {
      _prompting = false;
    }
  }

  late final _router = ExpiryPushRouter(
    loadJob: (id) async =>
        (await FirebaseFirestore.instance
                .collection('service_requests')
                .doc(id)
                .get())
            .data(),
    navigate: (id) async {
      await navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => ClientRequestDetailsScreen(requestId: id),
        ),
      );
    },
    onError: () {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the request. Try Notifications when connected.',
            ),
          ),
        );
      }
    },
  );

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
    region: const String.fromEnvironment(
      'EXPIRY_FUNCTIONS_REGION',
      defaultValue: 'us-central1',
    ),
  );

  Future<void> initialize() async {
    if (Firebase.app().options.projectId.startsWith('demo-')) return;
    if (!enabled ||
        kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid:
            kDebugMode && const bool.fromEnvironment('PUSH_APP_CHECK_DEBUG')
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple:
            kDebugMode && const bool.fromEnvironment('PUSH_APP_CHECK_DEBUG')
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
      // Auto-init remains off until the user gives informed consent.
      _initialized = true;
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      return;
    }
    FirebaseMessaging.onBackgroundMessage(expiryBackgroundMessage);
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_readyUid != null && user?.uid != _readyUid) {
        // Remove any previously opened owned details before another account uses
        // the navigator; async lookups are separately fenced by the router.
        navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
      _generation++;
      _foregroundEvents.clear();
      _readyUid = null;
      unawaited(_router.ready(null));
      unawaited(_activityRouter.ready(null));
      // Rotate on account/session changes. Old account tokens then become invalid.
      _registration = _registration
          .then((_) async {
            await FirebaseMessaging.instance.deleteToken();
            _token = null;
          })
          .catchError((Object _) {});
    });
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => queueOpen(message.data),
    );
    FirebaseMessaging.onMessage.listen((message) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (message.data['recipientId'] != uid || uid == null) return;
      final preferences = await this.preferences();
      if (_readyUid != uid || FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      if (preferences['enabled'] != true ||
          (message.data['type'] == 'chatMessage'
              ? preferences['chats'] != true
              : preferences['activities'] != true)) {
        return;
      }
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final event = message.data['eventId'];
      if (event is! String ||
          !validPushDocumentId(event) ||
          !_foregroundEvents.add(event)) {
        return;
      }
      if (_foregroundEvents.length > 100) {
        _foregroundEvents.remove(_foregroundEvents.first);
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            message.data['type'] == 'chatMessage'
                ? 'You have a new message.'
                : 'You have a SwiftServe update.',
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => queueOpen(message.data),
          ),
        ),
      );
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (_readyUid != null) unawaited(_register(token));
    });
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) queueOpen(initial.data);
    } catch (_) {
      /* Optional push must never block login. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _readyUid;
    if (state == AppLifecycleState.resumed && uid != null) {
      unawaited(_activate(uid));
    }
  }

  void profileReady(String uid) {
    if (!_initialized || _readyUid == uid) return;
    _readyUid = uid;
    unawaited(_activate(uid));
    unawaited(_router.ready(uid));
    unawaited(_activityRouter.ready(uid));
    unawaited(_explainOnce(uid));
  }

  Future<void> _activate(String uid) async {
    final generation = _generation;
    try {
      await _registration;
      if (generation != _generation || _readyUid != uid) return;
      final prefs = await preferences();
      if (prefs['enabled'] != true) return;
      final permission = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        if (_token != null) {
          await _register(_token!, forceDisabled: true);
          await FirebaseMessaging.instance.deleteToken();
          _token = null;
        }
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        return;
      }
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (generation == _generation && _readyUid == uid && token != null) {
        await _register(token);
      }
    } catch (_) {
      // Push is optional; errors never block sign-in or expose tokens in logs.
    }
  }

  Future<void> _register(String token, {bool forceDisabled = false}) {
    final uid = _readyUid;
    final generation = _generation;
    _registration = _registration.catchError((Object _) {}).then((_) async {
      if (_readyUid != uid || _generation != generation) return;
      await _performRegister(token, forceDisabled: forceDisabled);
    });
    return _registration;
  }

  Future<void> _performRegister(
    String token, {
    bool forceDisabled = false,
  }) async {
    final uid = _readyUid;
    final generation = _generation;
    if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _installation ??= prefs.getString('expiryPushInstallation');
      _installation ??= List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('expiryPushInstallation', _installation!);
      if (_generation != generation ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      final choices = await preferences();
      final permission = await FirebaseMessaging.instance
          .getNotificationSettings();
      final permitted = [
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ].contains(permission.authorizationStatus);
      if (_generation != generation ||
          _readyUid != uid ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      await _functions.httpsCallable('registerPushDevice').call({
        ...choices,
        'enabled': !forceDisabled && permitted && choices['enabled'] == true,
        'installationId': _installation,
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      });
      if (_generation != generation) {
        await FirebaseMessaging.instance.deleteToken();
        return;
      }
      _token = token;
    } catch (_) {
      /* Retry on next profile session/token refresh; never log token. */
    }
  }

  /// Call before FirebaseAuth.signOut while credentials still exist.
  Future<void> beforeSignOut() async {
    if (!enabled) return;
    _generation++;
    _readyUid = null;
    await _router.ready(null);
    await _activityRouter.ready(null);
    try {
      if (_token != null && _installation != null) {
        await _functions
            .httpsCallable('registerPushDevice')
            .call({
              'installationId': _installation,
              'token': _token,
              'revoke': true,
              'platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
            })
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      /* Local token invalidation remains necessary if offline. */
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
    _token = null;
  }

  void queueOpen(Map<String, dynamic> data) {
    if (!enabled) return;
    if (data['type'] == 'jobExpired') {
      unawaited(_router.queue(data));
    } else {
      unawaited(_activityRouter.queue(data));
    }
  }
}
