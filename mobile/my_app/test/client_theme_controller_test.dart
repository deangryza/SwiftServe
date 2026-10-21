import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/services/client_theme_controller.dart';

void main() {
  tearDown(() => ClientThemeController.darkMode.value = false);

  testWidgets('pushed client routes react to dark mode changes', (
    tester,
  ) async {
    ClientThemeController.darkMode.value = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ClientThemeScope(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  clientPageRoute(const _ThemeProbe()),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('light'), findsOneWidget);

    ClientThemeController.darkMode.value = true;
    await tester.pump();
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('client tab routes use the shared animated transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                clientTabPageRoute(
                  const _TabDestination(),
                  fromIndex: 0,
                  toIndex: 1,
                ),
              ),
              child: const Text('Bookings'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Bookings'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.byKey(const ValueKey('client-tab-transition'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('Booking screen'), findsOneWidget);
  });

  testWidgets('horizontal swipes select adjacent client tabs', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: ClientTabSwipeRegion(
          currentIndex: 1,
          onSwipeToIndex: (index) => selectedIndex = index,
          child: const Scaffold(
            body: SizedBox.expand(
              child: ColoredBox(
                key: ValueKey('swipe-surface'),
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('swipe-surface')),
      const Offset(-90, 0),
    );
    await tester.pump();
    expect(selectedIndex, 2);

    selectedIndex = null;
    await tester.drag(
      find.byKey(const ValueKey('swipe-surface')),
      const Offset(90, 0),
    );
    await tester.pump();
    expect(selectedIndex, 0);
  });
}

class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(Theme.of(context).brightness.name)));
}

class _TabDestination extends StatelessWidget {
  const _TabDestination();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Booking screen')));
}
