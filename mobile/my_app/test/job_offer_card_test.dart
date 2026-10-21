import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/worker/presentation/widgets/legacy/job_offer_card.dart';

void main() {
  testWidgets('shows location, price, and worker distance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobOfferCard(
            service: 'Need a carpenter',
            client: 'Client One',
            location: 'Malolos, Bulacan',
            price: '₱800',
            distanceLabel: '~2.4 km away',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Need a carpenter'), findsOneWidget);
    expect(find.textContaining('Malolos, Bulacan • ₱800'), findsOneWidget);
    expect(find.textContaining('~2.4 km away'), findsOneWidget);
  });

  testWidgets('shows the legacy distance fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JobOfferCard(
            service: 'Older request',
            client: 'Client Two',
            location: 'Bulacan',
            price: '₱500',
            distanceLabel: 'Distance unavailable',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Distance unavailable'), findsOneWidget);
  });
}
