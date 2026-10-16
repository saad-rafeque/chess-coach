import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../coach/coach_player.dart';
import '../coach/explain.dart';
import '../coach/preview_bot.dart';
import '../coach/quick_tips.dart';
import '../engine/analysis.dart';
import '../engine/engine_host.dart';

enum PlayMode { training, real }

enum CoachTone { info, good, warning, error, move }

class CoachMessage {
  const CoachMessage(this.text, this.tone);

  final String text;
  final CoachTone tone;
}

/// Depth for grading moves and for hints.
const feedbackDepth = 12;

const _praise = [
  'Excellent, that\'s the top engine move.',
  'Strong move!',
  'Exactly what I would play.',
  'Great find.',
];

/// A game against the coach: moves, engine feedback, hints and saving.
class GameController extends ChangeNotifier {
  GameController({required this.host, this.onSave, math.Random? random}) : _rnd = random ?? math.Random();

  final EngineHost host;

  /// Receives the game as JSON after each move, or null when it's finished.
  final void Function(String? json)? onSave;
  final math.Random _rnd;

  final positions = <Position>[Chess.initial];
  final moves = <NormalMove>[];
  final sans = <String>[];
  final chat = <CoachMessage>[];

  /// Grade of the player's move at each ply index.
  final grades = <int, MoveQuality>{};

  Side playerSide = Side.white;
  int coachElo = 800;
  PlayMode mode = PlayMode.training;
  bool hintsEnabled = true;
  bool thinking = false;
  bool resigned = false;

  /// Latest known evaluation (White's point of view).
  Score? evaluation;

  /// Move to draw on the board: a hint or the better move after an error.
  NormalMove? arrow;

  /// Square to highlight for a first-level hint.
  Square? highlight;

  Analysis? _analysis;
  int _hintLevel = 0;
  int _token = 0;
  bool _engineNoticeShown = false;

  Position get position => positions.last;
  bool get isOver => resigned || position.isGameOver;
  bool get playerToMove => !isOver && !thinking && position.turn == playerSide;
  bool get canUndo => _playerMoveCount > 0;
  int get _playerMoveCount => [for (var i = 0; i < moves.length; i++) positions[i].turn].where((s) => s == playerSide).length;
  NormalMove? get lastMove => moves.isEmpty ? null : moves.last;

  // ---- game flow ----

  void newGame({required Side side, required int elo}) {
    _token++;
    positions
      ..clear()
      ..add(Chess.initial);
    moves.clear();
    sans.clear();
    chat.clear();
    grades.clear();
    playerSide = side;
    coachElo = elo;
    resigned = false;
    thinking = false;
    _clearMarks();
    evaluation = null;
    _analysis = null;
    _say('New game! You play ${_name(side)}, I play at about $elo. '
        '${mode == PlayMode.training ? 'In Training mode I comment on every move.' : 'Real game: I stay quiet until the end.'}',
        CoachTone.info);
    _save();
    notifyListeners();
    if (side == Side.black) {
      unawaited(_coachMove(_token));
    } else {
      unawaited(_analyseCurrent());
    }
  }

  /// Restores a game saved by [onSave]. Returns false if [json] is unusable.
  bool restore(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final side = data['side'] == 'black' ? Side.black : Side.white;
      final restored = <Position>[Chess.initial];
      final restoredMoves = <NormalMove>[];
      final restoredSans = <String>[];
      for (final uci in (data['moves'] as List<dynamic>).cast<String>()) {
        final m = NormalMove.fromUci(uci);
        if (!restored.last.isLegal(m)) return false;
        final (next, san) = restored.last.makeSan(m);
        restored.add(next);
        restoredMoves.add(m);
        restoredSans.add(san);
      }
      _token++;
      positions
        ..clear()
        ..addAll(restored);
      moves
        ..clear()
        ..addAll(restoredMoves);
      sans
        ..clear()
        ..addAll(restoredSans);
      chat.clear();
      grades.clear();
      playerSide = side;
      coachElo = data['elo'] as int? ?? 800;
      mode = data['mode'] == 'real' ? PlayMode.real : PlayMode.training;
      resigned = false;
      thinking = false;
      _clearMarks();
      _say('Welcome back! Your game is just as you left it.', CoachTone.info);
      notifyListeners();
      if (!isOver && position.turn != playerSide) {
        unawaited(_coachMove(_token));
      } else {
        unawaited(_analyseCurrent());
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void setMode(PlayMode m) {
    if (m == mode) return;
    mode = m;
    if (m == PlayMode.real) _clearMarks();
    _say(m == PlayMode.training ? 'Training mode: I\'ll comment on your moves.' : 'Real game: I\'ll stay quiet until the game ends.',
        CoachTone.info);
    _save();
    notifyListeners();
  }

  Future<void> playerMove(NormalMove move) async {
    if (!playerToMove || !position.isLegal(move)) return;
    final token = _token;
    final before = position;
    final beforeAnalysis = _analysis?.fen == before.fen ? _analysis : null;
    _push(move);
    _clearMarks();
    thinking = true;
    _save();
    notifyListeners();
    if (mode == PlayMode.training && hintsEnabled) {
      await _feedback(before, move, beforeAnalysis, token);
      if (token != _token) return;
    }
    if (isOver) {
      thinking = false;
      _announce();
      return;
    }
    await _coachMove(token);
  }

  Future<void> _feedback(Position before, NormalMove move, Analysis? beforeAnalysis, int token) async {
    final after = position;
    final engine = await host.engine;
    if (engine == null || after.isGameOver) {
      _engineNotice(engine == null);
      final tip = tipForMove(before, move, after);
      if (tip != null) _say(tip.text, _toneFor(tip.kind));
      notifyListeners();
      return;
    }
    beforeAnalysis ??= await engine.analyse(before.fen, depth: feedbackDepth);
    final afterAnalysis = await engine.analyse(after.fen, depth: feedbackDepth);
    if (token != _token) return;
    evaluation = afterAnalysis.score ?? evaluation;
    final best = beforeAnalysis.bestMove;
    final bestMove = best == null ? null : Move.parse(best);
    final playedBest = bestMove != null && before.isLegal(bestMove) && before.play(bestMove).fen == after.fen;
    final quality = classifyMove(
      before: beforeAnalysis.score ?? const Score.cp(0),
      after: afterAnalysis.score ?? const Score.cp(0),
      moverIsWhite: before.turn == Side.white,
      playedBest: playedBest,
    );
    grades[moves.length - 1] = quality;
    if (quality.isError) {
      final why = explainError(
          quality: quality, before: before, beforeAnalysis: beforeAnalysis, after: after, afterAnalysis: afterAnalysis);
      _say('${quality.label}. $why', quality == MoveQuality.blunder ? CoachTone.error : CoachTone.warning);
      if (bestMove is NormalMove) arrow = bestMove;
    } else {
      final tip = tipForMove(before, move, after);
      if (tip != null && tip.kind != TipKind.warning) {
        _say(tip.text, _toneFor(tip.kind));
      } else if (quality == MoveQuality.best && _rnd.nextDouble() < 0.4) {
        _say(_praise[_rnd.nextInt(_praise.length)], CoachTone.good);
      }
    }
    notifyListeners();
  }

  Future<void> _coachMove(int token) async {
    thinking = true;
    notifyListeners();
    final started = DateTime.now();
    final engine = await host.engine;
    var move = pickPreviewMove(position, _rnd);
    if (engine != null) {
      final a = await engine.analyse(position.fen,
          depth: depthForElo(coachElo), multiPv: candidatesForElo(coachElo));
      if (token != _token) return;
      final picked = Move.parse(pickHumanMove(a, coachElo, _rnd));
      if (picked is NormalMove && position.isLegal(picked)) move = picked;
    } else {
      _engineNotice(true);
    }
    final lastWasError = grades[moves.length - 1]?.isError ?? false;
    final wait = Duration(milliseconds: 450 + _rnd.nextInt(500) + (lastWasError ? 1500 : 0));
    final elapsed = DateTime.now().difference(started);
    if (elapsed < wait) await Future<void>.delayed(wait - elapsed);
    if (token != _token) return;
    final captured = position.board.pieceAt(move.to);
    _push(move);
    _clearMarks();
    if (mode == PlayMode.training) {
      final took = captured != null && captured.color == playerSide ? ', taking your ${captured.role.name}' : '';
      _say('I played ${sans.last}$took.', CoachTone.move);
    }
    thinking = false;
    _save();
    notifyListeners();
    if (isOver) {
      _announce();
    } else {
      unawaited(_analyseCurrent());
    }
  }

  Future<void> _analyseCurrent() async {
    final token = _token;
    final engine = await host.engine;
    if (engine == null || position.isGameOver) return;
    final fen = position.fen;
    final a = await engine.analyse(fen, depth: feedbackDepth);
    if (token != _token || position.fen != fen) return;
    _analysis = a;
    evaluation = a.score ?? evaluation;
    notifyListeners();
  }

  // ---- player tools ----

  Future<void> hint() async {
    if (!playerToMove) return;
    final engine = await host.engine;
    if (engine == null) {
      for (final m in legalMoves(position)) {
        final piece = freeCapture(position, m);
        if (piece != null) {
          _say('Hint: the ${piece.role.name} on ${m.to.name} is not defended.', CoachTone.info);
          notifyListeners();
          return;
        }
      }
      _say('Hint: develop a piece, control the centre or make your king safer.', CoachTone.info);
      notifyListeners();
      return;
    }
    final fen = position.fen;
    final a = _analysis?.fen == fen ? _analysis! : await engine.analyse(fen, depth: feedbackDepth);
    if (position.fen != fen || a.bestMove == null) return;
    _analysis = a;
    final m = Move.parse(a.bestMove!);
    if (m is! NormalMove) return;
    final piece = position.board.pieceAt(m.from);
    if (_hintLevel == 0 && piece != null) {
      highlight = m.from;
      _hintLevel = 1;
      _say('Hint: look at your ${piece.role.name} on ${m.from.name}. Tap Hint again for the move.', CoachTone.info);
    } else {
      arrow = m;
      highlight = null;
      _hintLevel = 2;
      _say('Hint: ${sanOf(position, a.bestMove!)}.', CoachTone.info);
    }
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _token++;
    thinking = false;
    var removedPlayerMove = false;
    while (moves.isNotEmpty && !(removedPlayerMove && position.turn == playerSide)) {
      if (positions[positions.length - 2].turn == playerSide) removedPlayerMove = true;
      positions.removeLast();
      moves.removeLast();
      sans.removeLast();
      grades.remove(moves.length);
    }
    resigned = false;
    _clearMarks();
    _analysis = null;
    _say('Move taken back. Take your time and check for threats.', CoachTone.info);
    _save();
    notifyListeners();
    if (position.turn == playerSide) {
      unawaited(_analyseCurrent());
    } else {
      unawaited(_coachMove(_token));
    }
  }

  void resign() {
    if (isOver || moves.isEmpty) return;
    _token++;
    thinking = false;
    resigned = true;
    _clearMarks();
    _announce();
  }

  // ---- helpers ----

  void _announce() {
    final p = position;
    if (resigned) {
      _say('You resigned. Every lost game is a lesson.', CoachTone.info);
    } else if (p.isCheckmate) {
      p.turn != playerSide
          ? _say('Checkmate! You won. Excellent finish.', CoachTone.good)
          : _say('Checkmate. Let\'s learn from it.', CoachTone.warning);
    } else {
      _say(p.isStalemate ? 'Stalemate: the game is a draw.' : 'The game is a draw.', CoachTone.info);
    }
    final errors = grades.values.where((q) => q.isError).toList();
    if (grades.isNotEmpty) {
      int count(MoveQuality q) => errors.where((e) => e == q).length;
      _say(
          'Your game: ${count(MoveQuality.blunder)} blunders, ${count(MoveQuality.mistake)} mistakes, '
          '${count(MoveQuality.inaccuracy)} inaccuracies.',
          CoachTone.info);
    }
    _save();
    notifyListeners();
  }

  void _push(NormalMove move) {
    final (next, san) = position.makeSan(move);
    positions.add(next);
    moves.add(move);
    sans.add(san);
  }

  void _clearMarks() {
    arrow = null;
    highlight = null;
    _hintLevel = 0;
  }

  void _say(String text, CoachTone tone) => chat.add(CoachMessage(text, tone));

  void _engineNotice(bool missing) {
    if (!missing || _engineNoticeShown) return;
    _engineNoticeShown = true;
    _say('Stockfish isn\'t available here, so I\'m using simple rules for now.', CoachTone.warning);
  }

  void _save() {
    onSave?.call(isOver
        ? null
        : jsonEncode({
            'side': playerSide.name,
            'elo': coachElo,
            'mode': mode.name,
            'moves': [for (final m in moves) m.uci],
          }));
  }

  static CoachTone _toneFor(TipKind k) => switch (k) {
        TipKind.good => CoachTone.good,
        TipKind.warning => CoachTone.warning,
        TipKind.info => CoachTone.info,
      };

  static String _name(Side s) => s == Side.white ? 'White' : 'Black';

  @override
  void dispose() {
    _token++;
    super.dispose();
  }
}
