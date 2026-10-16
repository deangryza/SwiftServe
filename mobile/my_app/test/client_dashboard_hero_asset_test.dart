import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  test('third client hero contains its Plus card and complete CTA', () {
    final source = File('assets/dashboard/hero_plus.svg').readAsStringSync();

    expect(source, contains('id="plus-card"'));
    expect(source, contains('>PLUS</text>'));
    expect(source, contains('id="try-plus-button"'));
    expect(source, contains('Try Plus · &#8369;99/mo'));
  });

  testWidgets('third client hero renders through flutter_svg', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            height: 168,
            child: SvgPicture.asset('assets/dashboard/hero_plus.svg'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
