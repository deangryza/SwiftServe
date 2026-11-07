// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/firebase_bootstrap.dart';

class _Auth extends Fake implements FirebaseAuth {
  final List<Object> calls = [];
  @override
  Future<void> useAuthEmulator(
    String host,
    int port, {
    bool automaticHostMapping = true,
  }) async {
    calls.add([host, port, automaticHostMapping]);
  }
}

class _Firestore extends Fake implements FirebaseFirestore {
  final List<Object> calls = [];
  @override
  void useFirestoreEmulator(
    String host,
    int port, {
    bool sslEnabled = false,
    bool automaticHostMapping = true,
  }) {
    calls.add([host, port, automaticHostMapping]);
  }
}

class _Functions extends Fake implements FirebaseFunctions {
  final List<Object> calls = [];
  @override
  void useFunctionsEmulator(
    String host,
    int port, {
    bool automaticHostMapping = true,
  }) {
    calls.add([host, port, automaticHostMapping]);
  }
}

void main() {
  for (final host in ['127.0.0.1', 'localhost', '10.0.2.2']) {
    test(
      'preserves explicit $host addressing for all three Firebase services',
      () async {
        final auth = _Auth();
        final firestore = _Firestore();
        final functions = _Functions();
        await connectSwiftServeEmulators(
          host,
          auth: auth,
          firestore: firestore,
          functions: functions,
        );
        expect(auth.calls, [
          [host, 9099, false],
        ]);
        expect(firestore.calls, [
          [host, 8187, false],
        ]);
        expect(functions.calls, [
          [host, 5001, false],
        ]);
      },
    );
  }
  test('rejects remote hosts before configuring any service', () async {
    final auth = _Auth();
    final firestore = _Firestore();
    final functions = _Functions();
    await expectLater(
      connectSwiftServeEmulators(
        'example.com',
        auth: auth,
        firestore: firestore,
        functions: functions,
      ),
      throwsStateError,
    );
    expect(auth.calls, isEmpty);
    expect(firestore.calls, isEmpty);
    expect(functions.calls, isEmpty);
  });
}
