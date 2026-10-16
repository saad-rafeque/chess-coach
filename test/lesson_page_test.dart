import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/lessons/progress.dart';
import 'package:chess_coach/main.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons, Size;
import 'package:flutter_test/flutter_test.dart';

Future<EventStore> _openFirstLesson(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = EventStore.memory();
  await tester.pumpWidget(ChessCoachApp(settings: AppSettings.memory(), store: store));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lessons').last);
  await tester.pumpAndSettle();
  expect(find.text('0 / 20 done'), findsOneWidget);
  await tester.tap(find.text('Opening principles'));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('lesson player records steps and shows progress', (tester) async {
    final store = await _openFirstLesson(tester, const Size(1400, 900));
    expect(find.textContaining('Step 1 of 7'), findsOneWidget);
    expect(find.text('Learn'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 2 of 7'), findsOneWidget);
    expect(find.text('Find the move'), findsOneWidget);
    expect(find.text('Your move as White.'), findsOneWidget);

    // Revealing the answer completes the step but counts as a miss.
    await tester.tap(find.text('Show answer'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('The answer: e4.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final events = store.ofType(lessonEventType).toList();
    expect(events.length, 2);
    expect(events.last.data['solved'], false);

    // Leaving and coming back resumes at step 3; Home offers to continue.
    await tester.tap(find.byIcon(FluentIcons.back));
    await tester.pumpAndSettle();
    expect(find.text('2/7'), findsOneWidget);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Continue lesson'), findsOneWidget);
    await tester.tap(find.text('Opening principles'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Step 3 of 7'), findsOneWidget);
  });

  testWidgets('lesson player fits a phone screen', (tester) async {
    await _openFirstLesson(tester, const Size(390, 844));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Show answer'), findsOneWidget);
  });
}
