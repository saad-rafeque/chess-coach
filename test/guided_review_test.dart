import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/coach/coach_player.dart';
import 'package:chess_coach/coach/explain.dart';
import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/review/game_review.dart';
import 'package:chess_coach/review/guided_review.dart';
import 'package:chess_coach/screens/home_page.dart';
import 'package:chess_coach/screens/review_page.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<GameReview> _review() async {
  final store = await storeWithReviewedGame();
  final game = GameRecord.fromEvent(store.ofType(GameRecord.eventType).single);
  return buildReview(game, GameAnalysis.fromData(store.ofType(GameAnalysis.eventType).single.data));
}

void main() {
  test('lines are written with move numbers', () {
    expect(sanLine(Chess.initial, 0, ['e2e4', 'e7e5', 'g1f3']), '1. e4 e5 2. Nf3');
    final afterE4 = Chess.initial.play(Move.parse('e2e4')!);
    expect(sanLine(afterE4, 1, ['e7e5', 'g1f3']), '1… e5 2. Nf3');
    expect(sanLine(Chess.initial, 0, ['e2e4', 'e2e4']), '1. e4', reason: 'stops at an illegal move');
  });

  test('each focus picks the right moves, and the advice fits the error', () async {
    final review = await _review();
    final blunders = guidedSteps(review, ReviewFocus.blunders);
    expect(blunders.map((m) => m.san), ['Nf6']);
    expect(blunders.single.errorKind, ErrorKind.allowsMate);
    expect(guidedSteps(review, ReviewFocus.wholeGame).length, 3, reason: 'all of Black\'s moves');
    expect(guidedSteps(review, ReviewFocus.mistakes).every((m) => m.quality != MoveQuality.blunder), isTrue);
    expect(nextTimeTip(ErrorKind.allowsMate, Area.openings), contains('check'));
    expect(nextTimeTip(ErrorKind.worse, Area.openings), contains('castle'));
    expect(chancesText(blunders.single), contains('%'));
    expect(mainLesson(blunders, review.game.positions()), nextTimeTip(ErrorKind.allowsMate, Area.openings));
  });

  testWidgets('the coach goes through the blunders step by step', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = await storeWithReviewedGame();
    final game = GameRecord.fromEvent(store.ofType(GameRecord.eventType).single);
    final settings = AppSettings.memory()..coachName = 'Nova';
    await tester.pumpWidget(ChessCoachApp(settings: settings, store: store));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomePage));
    // ignore: unawaited_futures
    openReview(context, game, focus: ReviewFocus.blunders);
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 1'), findsOneWidget);
    expect(find.text('Move 3: you played Nf6'), findsOneWidget);
    expect(find.text('Better was g6'), findsOneWidget);
    expect(find.text('Next time'), findsOneWidget);
    expect(find.textContaining('3… Nf6 4. Qxf7#'), findsOneWidget, reason: 'where the move leads');

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('That\'s all your blunders'), findsOneWidget);
    expect(find.text('The lesson to keep'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Go through it with Nova'), findsOneWidget);
  });
}
