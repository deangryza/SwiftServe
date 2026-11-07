import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/client/presentation/screens/post_request_screen.dart';
import 'package:my_app/shared/models/app_user.dart';
import 'package:my_app/shared/models/service_request.dart';

const _banner = ValueKey('post-job-verification-required');
const _submit = ValueKey('post-job-submit');

// Online jobs skip the map/geocoding picker, which needs platform plugins.
ServiceRequest _onlineJob() => ServiceRequest.fromMap('job', {
  'title': 'Tutoring',
  'category': 'Other',
  'budget': 200,
  'description': 'Help with homework',
  'modality': 'online',
});

Future<void> _pump(
  WidgetTester tester,
  VerificationStatus status, {
  ServiceRequest? existing,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PostRequestScreen(
        existing: existing,
        // A repost creates a new job, exactly like a fresh post.
        repostOf: existing == null ? _onlineJob() : null,
        categoryNames: Stream.value(['Other']),
        accountVerification: Stream.value(status),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(_submit)).onPressed != null;

void main() {
  for (final status in VerificationStatus.values.where(
    (status) => status != VerificationStatus.verified,
  )) {
    testWidgets('unverified ($status) client cannot post a job', (
      tester,
    ) async {
      await _pump(tester, status);
      expect(find.byKey(_banner), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);
    });
  }

  testWidgets('verified client can post a job', (tester) async {
    await _pump(tester, VerificationStatus.verified);
    expect(find.byKey(_banner), findsNothing);
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('editing an existing post is not blocked', (tester) async {
    await _pump(tester, VerificationStatus.pending, existing: _onlineJob());
    expect(find.byKey(_banner), findsNothing);
    expect(_submitEnabled(tester), isTrue);
  });
}
