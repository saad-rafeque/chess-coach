import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/review/game_review.dart';

/// A store holding one lost game (Black blunders into Scholar's mate) and its review.
Future<EventStore> storeWithReviewedGame() async {
  final store = EventStore.memory();
  const moves = ['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7'];
  await store.add(GameRecord.eventType, {
    'side': 'black', 'elo': 800, 'moves': moves, 'result': '1-0', 'ending': 'checkmate',
  }, id: 'g1');
  await store.add(
      GameAnalysis.eventType,
      const GameAnalysis(scores: [
        Score.cp(20), Score.cp(30), Score.cp(25), Score.cp(-20), Score.cp(-10), Score.cp(0), Score.mate(1),
        Score.cp(10000),
      ], best: [
        'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g7g6', 'h5f7', null,
      ]).toData('g1'));
  return store;
}
