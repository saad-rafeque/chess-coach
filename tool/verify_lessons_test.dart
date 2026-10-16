// Checks every "find the move" lesson step with Stockfish and prints a report.
// Run locally (needs engines/linux/stockfish): flutter test tool/verify_lessons_test.dart
// Optional: LESSON=<id> to check one lesson.
import 'dart:io';

import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/uci_process.dart';
import 'package:chess_coach/lessons/lesson.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';

/// Score for the side to move in [pos].
int _forMover(Score s, Position pos) => pos.turn == Side.white ? s.value : -s.value;

void main() {
  test('lesson moves agree with Stockfish', () async {
    final path = '${Directory.current.path}/engines/linux/stockfish';
    if (!File(path).existsSync()) {
      markTestSkipped('Stockfish binary not fetched');
      return;
    }
    final only = Platform.environment['LESSON'];
    final engine = await ChessEngine.start(process: await DesktopUciProcess.start(path));
    final problems = <String>[];
    for (final lesson in allLessons) {
      if (only != null && lesson.id != only) continue;
      for (final (i, step) in lesson.steps.indexed) {
        if (step.kind != StepKind.find) continue;
        final b = step.resolve();
        var pos = b.start;
        for (var k = 0; k < b.solution.length; k++) {
          final move = Move.parse(b.solution[k])!;
          if (k.isEven) {
            final a = await engine.analyse(pos.fen, movetime: const Duration(milliseconds: 1500), multiPv: 4);
            final best = _forMover(a.score!, pos);
            final after = pos.play(move);
            final reply = after.isGameOver ? null : await engine.analyse(after.fen, movetime: const Duration(seconds: 1));
            final mine = after.isCheckmate ? 10000 : (reply == null ? 0 : -_forMover(reply.score!, after));
            final close = [
              for (final l in a.lines)
                if ((best - _forMover(l.score, pos)).abs() <= 40) _san(pos, l.move),
            ];
            final loss = best - mine;
            final winning = best > 600 && mine > 600;
            final tag = '${lesson.id} step ${i + 1} move ${k ~/ 2 + 1} ${b.solutionSan[k]}';
            final line = '$tag: mine $mine, best $best ${_san(pos, a.bestMove!)}, near-best ${close.join(' ')}';
            stdout.writeln(line);
            if (loss > 60 && !winning) problems.add(line);
          }
          pos = pos.play(move);
        }
      }
    }
    await engine.dispose();
    stdout.writeln('\n${problems.length} problems');
    problems.forEach(stdout.writeln);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

String _san(Position pos, String uci) {
  final m = Move.parse(uci);
  return m == null || !pos.isLegal(m) ? uci : pos.makeSan(m).$2;
}
