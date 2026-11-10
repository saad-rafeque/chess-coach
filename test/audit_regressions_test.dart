import 'dart:async';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/engine/uci_process.dart';
import 'package:chess_coach/lessons/lesson.dart';
import 'package:chess_coach/lessons/progress.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/train/cards.dart';
import 'package:chess_coach/train/fsrs.dart';
import 'package:chess_coach/train/skill_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_test.dart' show FakeUci;

void main() {
  test('disposing during engine startup closes the late engine safely', () async {
    final ready = Completer<ChessEngine>();
    final host = EngineHost(starter: () => ready.future);
    final starting = host.engine;
    final closing = host.dispose();
    final engine = ChessEngine(FakeUci({}));
    ready.complete(engine);
    expect(await starting, isNull);
    await closing;
    expect(engine.isClosed, isTrue);
    expect(await host.engine, isNull);
    await host.dispose();
  });

  test('a failed engine is replaced on the next request', () async {
    var starts = 0;
    final host = EngineHost(starter: () async {
      starts++;
      return ChessEngine(FakeUci({}));
    });
    final first = (await host.engine)!;
    await first.dispose();
    expect(await host.engine, isNot(same(first)));
    expect(starts, 2);
    await host.dispose();
  });

  test('late stopped bestmove never leaks into the next search', () async {
    final process = _LateStopUci();
    final engine = await ChessEngine.start(process: process);
    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final first = engine.analyse(fen, searchTimeout: const Duration(milliseconds: 5));
    final firstCheck = expectLater(first, throwsA(isA<TimeoutException>()));
    final second = engine.analyse(fen);
    await firstCheck;
    expect((await second).bestMove, 'b1c3');
    await engine.dispose();
  });

  test('streak cache refreshes when the local date changes', () async {
    final store = EventStore.memory();
    final today = DateTime(2026, 11, 8, 12);
    await store.merge([AppEvent(id: 'daily', type: cardEventType,
      time: today.toUtc(), device: 'test', data: {'id': 'card', 'grade': 3})]);
    expect(SkillModel.of(store, now: today).activeToday, isTrue);
    final tomorrow = SkillModel.of(store, now: DateTime(2026, 11, 9, 12));
    expect(tomorrow.activeToday, isFalse);
    expect(tomorrow.streakDays, 1);
    expect(SkillModel.of(store, now: DateTime(2026, 11, 10, 12)).streakDays, 0);
  });

  test('new-card daily quota resets without adding another event', () async {
    final store = EventStore.memory();
    final today = DateTime(2026, 11, 8, 12);
    final events = <AppEvent>[];
    for (final lesson in allLessons) {
      for (final (i, step) in lesson.steps.indexed) {
        if (step.kind != StepKind.find) continue;
        events.add(AppEvent(id: 'lesson-${lesson.id}-$i', type: lessonEventType,
          time: today.subtract(const Duration(days: 1)).toUtc(), device: 'test',
          data: lessonStepData(lesson, i, solved: false)));
      }
    }
    await store.merge(events);
    final cards = CardDeck.of(store, now: today).cards;
    expect(cards.length, greaterThan(10));
    await store.merge([
      for (final card in cards.take(10)) AppEvent(id: 'review-${card.id}',
        type: cardEventType, time: today.toUtc(), device: 'test',
        data: cardReviewData(card, Grade.good)),
    ]);
    expect(CardDeck.of(store, now: today).due(now: today), isEmpty);
    final tomorrow = DateTime(2026, 11, 9, 12);
    expect(CardDeck.of(store, now: tomorrow).due(now: tomorrow), hasLength(10));
  });

  test('memory settings retain one installation identity', () {
    final settings = AppSettings.memory();
    expect(settings.deviceId, settings.deviceId);
  });

  testWidgets('Home refreshes its saved-game action on return', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings.memory();
    await tester.pumpWidget(ChessCoachApp(settings: settings));
    await tester.pumpAndSettle();
    expect(find.text('Play the coach'), findsOneWidget);
    await tester.tap(find.text('Play').last);
    await tester.pumpAndSettle();
    expect(settings.savedGame, isNotNull);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    expect(find.text('Back to your game'), findsOneWidget);
  });
}

class _LateStopUci implements UciProcess {
  final _out = StreamController<String>.broadcast();
  int searches = 0;
  @override
  Stream<String> get lines => _out.stream;
  @override
  void send(String command) {
    if (command == 'uci') scheduleMicrotask(() => _out.add('uciok'));
    if (command == 'isready') scheduleMicrotask(() => _out.add('readyok'));
    if (command.startsWith('go') && ++searches == 2) {
      scheduleMicrotask(() => _out.add('bestmove b1c3'));
    }
    if (command == 'stop') {
      Timer(const Duration(milliseconds: 20), () => _out.add('bestmove e2e4'));
    }
  }
  @override
  Future<void> close() => _out.close();
}
