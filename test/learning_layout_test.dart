import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/app/theme.dart';
import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/lessons/lesson.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:chess_coach/screens/lesson_page.dart';
import 'package:chess_coach/screens/lessons_page.dart';
import 'package:chess_coach/screens/puzzles_page.dart';
import 'package:chess_coach/widgets/board_layout.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget page) => SettingsScope(
  settings: AppSettings.memory(),
  child: StoreScope(
    store: EventStore.memory(),
    child: PaletteScope(
      palette: Palette.dark,
      child: FluentApp(theme: buildFluentTheme(Palette.dark), home: page),
    ),
  ),
);

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.binding.handleMetricsChanged();
}

void main() {
  testWidgets('puzzle board is centred and hint highlights the correct piece', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        PuzzlesPage(
          bank: Future.value(
            PuzzleBank([
              PuzzleItem(
                id: 'test',
                fen: Chess.initial.fen,
                moves: const ['e2e4'],
                rating: 800,
                themes: const ['opening'],
                setup: false,
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final board = tester.getRect(find.byType(Chessboard));
    final area = tester.getRect(find.byType(BoardLayout));
    expect(board.width, 390);
    expect(board.center.dy, closeTo(area.center.dy, 1));
    expect(
      find.text('Find the best move for White.').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('Hint'), matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    await tester.tap(find.text('Hint').hitTestable());
    await tester.pumpAndSettle();
    expect(
      tester.widget<Chessboard>(find.byType(Chessboard)).shapes,
      contains(isA<Circle>().having((c) => c.orig, 'hint square', Square.e2)),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.text('Hint: look at your pawn on e2.').hitTestable(),
      findsOneWidget,
    );
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    _size(tester, const Size(320, 320));
    await tester.pumpAndSettle();
    expect(find.text('Hint').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lesson hint and instructions remain accessible in split screen', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    final lesson = allLessons.first;
    await tester.pumpWidget(_app(LessonPage(lesson: lesson, startStep: 1)));
    await tester.pumpAndSettle();
    final board = tester.getRect(find.byType(Chessboard));
    final area = tester.getRect(find.byType(BoardLayout));
    expect(board.width, 390);
    expect(board.center.dy, closeTo(area.center.dy, 1));
    await tester.tap(find.text('Hint').hitTestable());
    await tester.pumpAndSettle();
    expect(
      find.text('Hint: ${lesson.steps[1].hint}').hitTestable(),
      findsOneWidget,
    );
    for (final size in [const Size(320, 320), const Size(700, 320)]) {
      _size(tester, size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      // The full explanation must be reachable, not replaced by a hint-only panel.
      final open = find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Open Lesson guide suggestions',
          )
          .hitTestable();
      if (open.evaluate().isNotEmpty) {
        await tester.tap(open);
        await tester.pumpAndSettle();
      } else {
        await tester.ensureVisible(find.text('Open Lesson guide'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Lesson guide'));
        await tester.pumpAndSettle();
      }
      await Scrollable.ensureVisible(
        tester.element(find.text(lesson.steps[1].text)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(lesson.steps[1].text).hitTestable(),
        findsOneWidget,
        reason: '$size',
      );
      if (find
          .byIcon(FluentIcons.chrome_close)
          .hitTestable()
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byIcon(FluentIcons.chrome_close).hitTestable());
        await tester.pumpAndSettle();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'lesson library and completion fit narrow screens with large text',
    (tester) async {
      _size(tester, const Size(320, 480));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_app(const LessonsPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const lesson = Lesson(
        'layout-test',
        'A final step',
        'Finish a lesson',
        800,
        Area.openings,
        [LessonStep.show('Control the centre.')],
      );
      await tester.pumpWidget(_app(const LessonPage(lesson: lesson)));
      await tester.pumpAndSettle();
      final open = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Open Lesson guide suggestions',
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Finish').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish').last);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Lesson complete!')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(find.text('Lesson complete!').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('replaying a lesson demo immediately resets its board', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    const lesson = Lesson(
      'replay-test',
      'A demo',
      'Watch opening moves',
      800,
      Area.openings,
      [LessonStep.show('Control the centre.', demo: 'e4 e5')],
    );
    await tester.pumpWidget(
      _app(
        const LessonPage(
          lesson: lesson,
          demoDelay: Duration(milliseconds: 100),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<Chessboard>(find.byType(Chessboard))
        .controller;
    expect(controller.game.fen, isNot(Chess.initial.fen));
    await tester.tap(find.text('Replay'));
    await tester.pump();
    expect(controller.game.fen, Chess.initial.fen);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
