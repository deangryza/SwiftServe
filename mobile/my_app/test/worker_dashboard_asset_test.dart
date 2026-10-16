import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('worker dashboard hero banners load as SVG assets', (
    tester,
  ) async {
    const assets = [
      'assets/dashboard/worker_fees_banner.svg',
      'assets/dashboard/worker_banner_2.svg',
      'assets/dashboard/worker_banner_3.svg',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final asset in assets)
                Expanded(child: SvgPicture.asset(asset)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SvgPicture), findsNWidgets(3));
  });
}
