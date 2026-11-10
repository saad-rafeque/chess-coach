import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/review/game_review.dart';
import 'package:chess_coach/screens/home_page.dart';
import 'package:chess_coach/screens/review_page.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecoveringEngine implements ChessEngine {
  bool fail = true;
  @override
  bool isClosed = false;

  @override
  Future<Analysis> analyse(
    String fen, {
    int depth = 14,
    Duration? movetime,
    int multiPv = 1,
    Duration searchTimeout = const Duration(seconds: 60),
  }) async {
    if (fail) throw StateError('Search failed');
    final pos = Chess.fromSetup(Setup.parseFen(fen));
    final entry = pos.legalMoves.entries.firstWhere((e) => e.value.isNotEmpty);
    final uci = NormalMove(from: entry.key, to: entry.value.squares.first).uci;
    return Analysis(
      fen: fen,
      bestMove: uci,
      lines: [
        EngineLine(
          multipv: 1,
          depth: depth,
          score: const Score.cp(0),
          pv: [uci],
        ),
      ],
    );
  }

  @override
  Future<void> dispose() async {
    isClosed = true;
  }
}

Future<GameRecord> _game(EventStore store) async {
  final event = await store.add(GameRecord.eventType, {
    'side': 'white',
    'elo': 800,
    'moves': ['e2e4', 'e7e5'],
    'result': '0-1',
    'ending': 'resignation',
  }, id: 'recovery-game');
  return GameRecord.fromEvent(event);
}

Future<void> _open(
  WidgetTester tester,
  EventStore store,
  GameRecord game, {
  EngineHost? engine,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChessCoachApp(settings: AppSettings.memory(), store: store, engine: engine),
  );
  await tester.pumpAndSettle();
  // ignore: unawaited_futures
  openReview(tester.element(find.byType(HomePage)), game);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'search failure shows a retry and a successful retry stores the review',
    (tester) async {
      final store = EventStore.memory();
      final game = await _game(store);
      final engine = _RecoveringEngine();
      final host = EngineHost(starter: () async => engine);
      await _open(tester, store, game, engine: host);
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Could not finish this review'),
        findsOneWidget,
      );
      expect(store.ofType(GameAnalysis.eventType), isEmpty);
      engine.fail = false;
      await tester.tap(find.text('Retry review'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Your accuracy'), findsOneWidget);
      expect(store.ofType(GameAnalysis.eventType), hasLength(1));
      expect(find.text('Retry review'), findsNothing);
      await host.dispose();
    },
  );

  testWidgets('an incomplete cached review stays navigable without an engine', (
    tester,
  ) async {
    final store = EventStore.memory();
    final game = await _game(store);
    await store.add(
      GameAnalysis.eventType,
      const GameAnalysis(
        scores: [Score.cp(0), Score.cp(20)],
        best: ['e2e4', 'e7e5'],
      ).toData(game.id),
    );
    await _open(tester, store, game);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Game review needs Stockfish'), findsOneWidget);
    expect(find.text('Your accuracy'), findsNothing);
    await tester.tap(find.byTooltip('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('End'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an incomplete cached review is rebuilt when an engine is available',
    (tester) async {
      final store = EventStore.memory();
      final game = await _game(store);
      await store.add(
        GameAnalysis.eventType,
        const GameAnalysis(
          scores: [Score.cp(0)],
          best: ['e2e4'],
        ).toData(game.id),
      );
      final engine = _RecoveringEngine()..fail = false;
      final host = EngineHost(starter: () async => engine);
      await _open(tester, store, game, engine: host);
      expect(tester.takeException(), isNull);
      expect(find.text('Your accuracy'), findsOneWidget);
      final saved = GameAnalysis.fromData(
        store.ofType(GameAnalysis.eventType).last.data,
      );
      expect(saved.scores, hasLength(game.moves.length + 1));
      await host.dispose();
    },
  );
}
