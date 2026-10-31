import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/shared/widgets/chat_message_timeline.dart';

List<ChatMessageIdentity> history(
  int count, {
  int start = 0,
  String sender = 'other',
}) => [
  for (var i = start; i < start + count; i++)
    ChatMessageIdentity(id: 'message-$i', senderId: sender),
];

Widget timeline(
  List<ChatMessageIdentity> messages, {
  String room = 'room',
  double composerHeight = 60,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        Expanded(
          child: ChatMessageTimeline(
            conversationId: room,
            currentUserId: 'me',
            messages: messages,
            itemBuilder: (_, index) => SizedBox(
              key: ValueKey('bubble-${messages[index].id}'),
              height:
                  50 + (int.parse(messages[index].id.split('-').last) % 4) * 25,
              child: Text(messages[index].id),
            ),
          ),
        ),
        SizedBox(height: composerHeight),
      ],
    ),
  ),
);

ScrollController controller(WidgetTester tester, {String room = 'room'}) =>
    tester
        .widget<ListView>(find.byKey(ValueKey('chat-timeline-$room')))
        .controller!;

Future<void> readHistory(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 700));
  await tester.pumpAndSettle();
  expect(controller(tester).offset, greaterThan(80));
}

void main() {
  for (final role in ['Client', 'Worker']) {
    for (final count in [3, 2000]) {
      testWidgets(
        '$role opens $count messages at the latest, including variable heights',
        (tester) async {
          await tester.pumpWidget(timeline(history(count)));
          await tester.pumpAndSettle();
          expect(find.text('message-${count - 1}'), findsOneWidget);
          expect(
            controller(tester).offset,
            controller(tester).position.minScrollExtent,
          );
          if (count > 100) expect(find.text('message-0'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'async history arrival starts at latest without estimated extent retries',
    (tester) async {
      final stream = StreamController<List<ChatMessageIdentity>>();
      addTearDown(stream.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamBuilder<List<ChatMessageIdentity>>(
              stream: stream.stream,
              builder: (_, snapshot) => snapshot.hasData
                  ? ChatMessageTimeline(
                      conversationId: 'room',
                      currentUserId: 'me',
                      messages: snapshot.data!,
                      itemBuilder: (_, index) => SizedBox(
                        height: 80,
                        child: Text(snapshot.data![index].id),
                      ),
                    )
                  : const Text('Loading history'),
            ),
          ),
        ),
      );
      expect(find.text('Loading history'), findsOneWidget);
      stream.add(history(2000));
      await tester.pumpAndSettle();
      expect(find.text('message-1999'), findsOneWidget);
      expect(controller(tester).offset, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('incoming messages stay visible while near latest', (
    tester,
  ) async {
    await tester.pumpWidget(timeline(history(100)));
    await tester.pumpAndSettle();
    controller(tester).jumpTo(40);
    await tester.pumpWidget(timeline(history(101)));
    await tester.pumpAndSettle();
    expect(find.text('message-100'), findsOneWidget);
    expect(controller(tester).offset, 0);
    expect(find.byKey(const ValueKey('chat-new-messages')), findsNothing);
  });

  testWidgets(
    'incoming messages preserve older reading position until indicator is tapped',
    (tester) async {
      await tester.pumpWidget(timeline(history(100)));
      await tester.pumpAndSettle();
      await readHistory(tester);
      final offset = controller(tester).offset;
      final visible = tester
          .widget(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'bubble-',
                      ),
                )
                .hitTestable()
                .first,
          )
          .key!;
      final before = tester.getTopLeft(find.byKey(visible));
      await tester.pumpWidget(timeline(history(102)));
      await tester.pumpAndSettle();
      expect(controller(tester).offset, offset);
      expect(tester.getTopLeft(find.byKey(visible)), before);
      expect(find.text('message-101'), findsNothing);
      expect(find.text('New messages (2)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-new-messages')));
      await tester.pumpAndSettle();
      expect(find.text('message-101'), findsOneWidget);
      expect(controller(tester).offset, 0);
      expect(find.byKey(const ValueKey('chat-new-messages')), findsNothing);
    },
  );

  testWidgets(
    'a sent message scrolls to latest even while reading older messages',
    (tester) async {
      await tester.pumpWidget(timeline(history(100)));
      await tester.pumpAndSettle();
      await readHistory(tester);
      await tester.pumpWidget(
        timeline([...history(100), ...history(1, start: 100, sender: 'me')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('message-100'), findsOneWidget);
      expect(controller(tester).offset, 0);
    },
  );

  testWidgets(
    'older pagination does not act like a sent or received new message',
    (tester) async {
      final original = history(100, start: 100, sender: 'me');
      await tester.pumpWidget(timeline(original));
      await tester.pumpAndSettle();
      await readHistory(tester);
      final offset = controller(tester).offset;
      await tester.pumpWidget(
        timeline([...history(37, start: 63, sender: 'me'), ...original]),
      );
      await tester.pumpAndSettle();
      expect(controller(tester).offset, offset);
      expect(find.byKey(const ValueKey('chat-new-messages')), findsNothing);
    },
  );

  testWidgets(
    'same-ID acknowledgements and rebuilds do not move someone reading history',
    (tester) async {
      await tester.pumpWidget(timeline(history(100)));
      await tester.pumpAndSettle();
      await readHistory(tester);
      final offset = controller(tester).offset;
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(timeline(history(100)));
        await tester.pumpAndSettle();
        expect(controller(tester).offset, offset);
      }
    },
  );

  testWidgets(
    'changing conversation resets offset and discards pending messages',
    (tester) async {
      await tester.pumpWidget(timeline(history(100)));
      await tester.pumpAndSettle();
      await readHistory(tester);
      await tester.pumpWidget(timeline(history(101)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        timeline(history(300, start: 1000), room: 'other-room'),
      );
      await tester.pumpAndSettle();
      expect(controller(tester, room: 'other-room').offset, 0);
      expect(find.text('message-1299'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-new-messages')), findsNothing);
    },
  );

  testWidgets(
    'keyboard resize keeps the newest message visible while following',
    (tester) async {
      await tester.pumpWidget(timeline(history(100)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(timeline(history(100), composerHeight: 300));
      await tester.pumpAndSettle();
      expect(find.text('message-99'), findsOneWidget);
      expect(controller(tester).offset, 0);
    },
  );

  testWidgets('returning near latest reveals deferred messages', (
    tester,
  ) async {
    await tester.pumpWidget(timeline(history(100)));
    await tester.pumpAndSettle();
    await readHistory(tester);
    await tester.pumpWidget(timeline(history(103)));
    await tester.pumpAndSettle();
    controller(tester).jumpTo(20);
    await tester.pumpAndSettle();
    expect(find.text('message-102'), findsOneWidget);
    expect(controller(tester).offset, 0);
    expect(find.byKey(const ValueKey('chat-new-messages')), findsNothing);
  });

  testWidgets(
    'disposing during a scheduled latest jump does not use a disposed controller',
    (tester) async {
      await tester.pumpWidget(timeline(history(100)));
      await tester.pumpAndSettle();
      await readHistory(tester);
      await tester.pumpWidget(timeline(history(101)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-new-messages')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
