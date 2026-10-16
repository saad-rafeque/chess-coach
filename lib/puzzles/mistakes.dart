import '../coach/coach_player.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../review/game_review.dart';
import 'puzzle.dart';

/// Turns the player's mistakes and blunders in reviewed games into puzzles:
/// the position before the error, solved by the engine's best move.
List<PuzzleItem> mistakePuzzles(EventStore store) {
  final games = {for (final e in store.ofType(GameRecord.eventType)) e.id: GameRecord.fromEvent(e)};
  final out = <PuzzleItem>[];
  final seenIds = <String>{};
  for (final e in store.ofType(GameAnalysis.eventType)) {
    final game = games[e.data['game']];
    if (game == null) continue;
    final review = cachedReview(game, e);
    final positions = game.positions();
    for (final m in review.movesOf(game.playerSide)) {
      if (m.quality.index < MoveQuality.mistake.index || m.bestUci == null) continue;
      final id = 'mistake-${game.id}-${m.ply}';
      if (!seenIds.add(id)) continue;
      out.add(PuzzleItem(
        id: id,
        fen: positions[m.ply].fen,
        moves: [m.bestUci!],
        rating: game.coachElo,
        themes: const ['yourMistakes'],
        setup: false,
      ));
    }
  }
  return out;
}
