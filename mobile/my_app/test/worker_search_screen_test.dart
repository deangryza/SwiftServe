import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/screens/worker_search_screen.dart';
import 'package:my_app/shared/models/app_user.dart';

void main() {
  const worker = AppUser(
    id: 'worker-1',
    fullName: 'Worker One',
    email: 'worker@example.com',
    role: UserRole.worker,
    verificationStatus: VerificationStatus.verified,
  );

  testWidgets('worker search opens with saved history and search controls', (
    tester,
  ) async {
    final history = _FakeHistoryStore(['plumbing']);

    await tester.pumpWidget(
      MaterialApp(
        home: WorkerSearchScreen(worker: worker, historyStore: history),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('worker-search-field')), findsOneWidget);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('plumbing'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('plumbing'), findsNothing);
    expect(find.text('Your recent searches will appear here.'), findsOneWidget);
  });
}

class _FakeHistoryStore implements WorkerSearchHistoryStore {
  _FakeHistoryStore(this.searches);

  List<String> searches;

  @override
  Future<List<String>> load(String key) async => List.of(searches);

  @override
  Future<void> save(String key, List<String> searches) async {
    this.searches = List.of(searches);
  }

  @override
  Future<void> clear(String key) async => searches = [];
}
