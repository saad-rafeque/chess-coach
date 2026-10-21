import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../app/board_sound.dart';
import '../app/settings.dart';
import '../coach/coach_player.dart';
import '../coach/explain.dart';
import '../coach/preview_bot.dart';
import '../coach/quick_tips.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../engine/analysis.dart';
import '../engine/engine_host.dart';
import '../maia/maia_player.dart';

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
  GameController({
    required this.host,
    this.maia,
    this.onSave,
    this.onFinished,
    this.polish,
    this.settings,
    math.Random? random,
  }) : _rnd = random ?? math.Random();

  /// Optional friendlier rewording of an explanation (the local language model);
  /// null keeps the template text.
  final Future<String?> Function(String text)? polish;

  /// The player's preferences; null (tests) keeps sounds and haptics on.
  final AppSettings? settings;

  final EngineHost host;

  /// Human-like opponent for strengths up to [MaiaPlayer.maxElo]; Stockfish above that.
  final MaiaPlayer? maia;

  /// Called once when a game ends, with the record to archive.
  final void Function(GameRecord record)? onFinished;

  /// The most recently finished game (for review).
  GameRecord? lastRecord;

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

  /// Two humans on one device: no coach moves, no grading, and [hint] gives
  /// guidance to whichever side is to move. Games are not archived.
  bool twoPlayers = false;

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

  /// Whether the current board state has occurred 3 or more times.
  bool get isThreefoldRepetition {
    if (positions.length < 5) return false;
    final current = positions.last;
    var count = 0;
    for (final p in positions) {
      if (p.turn == current.turn &&
          p.board == current.board &&
          p.castles == current.castles &&
          p.epSquare == current.epSquare) {
        count++;
        if (count >= 3) return true;
      }
    }
    return false;
  }

  bool get isFiftyMoveDraw => position.halfmoves >= 100;
  bool get isOver =>
      resigned || position.isGameOver || isThreefoldRepetition || isFiftyMoveDraw;
  bool get playerToMove =>
      !isOver && !thinking && (twoPlayers || position.turn == playerSide);
  bool get canUndo => twoPlayers ? moves.isNotEmpty : _playerMoveCount > 0;
  int get _playerMoveCount => [
    for (var i = 0; i < moves.length; i++) positions[i].turn,
  ].where((s) => s == playerSide).length;
  NormalMove? get lastMove => moves.isEmpty ? null : moves.last;

  // ---- game flow ----

  void newGame({
    required Side side,
    required int elo,
    bool twoPlayers = false,
  }) {
    _token++;
    lastRecord = null;
    positions
      ..clear()
      ..add(Chess.initial);
    moves.clear();
    sans.clear();
    chat.clear();
    grades.clear();
    playerSide = side;
    coachElo = elo.clamp(400, 3200);
    resigned = false;
    thinking = false;
    this.twoPlayers = twoPlayers;
    _clearMarks();
    evaluation = null;
    _analysis = null;
    _say(
      twoPlayers
          ? 'Two players on one board: pass the device after each move. Either player can tap Hint '
                'and the coach suggests what to play.'
          : 'New game! You play ${_name(side)}, I play at about $coachElo. '
                '${mode == PlayMode.training ? 'In Training mode I comment on every move.' : 'Real game: I stay quiet until the end.'}',
      CoachTone.info,
    );
    _save();
    notifyListeners();
    if (twoPlayers)
      return; // both sides are human; nothing to analyse in the background
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
      final rawMoves = data['moves'];
      if (rawMoves is! List ||
          rawMoves.length > 1000 ||
          rawMoves.any((move) => move is! String)) {
        return false;
      }
      final restored = <Position>[Chess.initial];
      final restoredMoves = <NormalMove>[];
      final restoredSans = <String>[];
      for (final uci in rawMoves.cast<String>()) {
        final m = NormalMove.fromUci(uci);
        if (!restored.last.isLegal(m)) return false;
        final (next, san) = restored.last.makeSan(m);
        restored.add(next);
        restoredMoves.add(m);
        restoredSans.add(san);
      }
      _token++;
      lastRecord = null;
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
      final rawElo = data['elo'];
      coachElo = (rawElo is int ? rawElo : 800).clamp(400, 3200);
      mode = data['mode'] == 'real' ? PlayMode.real : PlayMode.training;
      twoPlayers = data['two'] == true;
      resigned = false;
      thinking = false;
      _clearMarks();
      _say('Welcome back! Your game is just as you left it.', CoachTone.info);
      notifyListeners();
      if (!twoPlayers && !isOver && position.turn != playerSide) {
        unawaited(_coachMove(_token));
      } else if (!twoPlayers) {
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
    _say(
      m == PlayMode.training
          ? 'Training mode: I\'ll comment on your moves.'
          : 'Real game: I\'ll stay quiet until the game ends.',
      CoachTone.info,
    );
    _save();
    notifyListeners();
  }

  Future<void> playerMove(NormalMove move) async {
    if (!playerToMove || !position.isLegal(move)) return;
    final token = _token;
    final before = position;
    final beforeAnalysis = _analysis?.fen == before.fen ? _analysis : null;
    _push(move);
    final captured = before.board.pieceAt(move.to);
    _sound(
      captured != null ? BoardSoundKind.capture : BoardSoundKind.move,
      buzz: captured != null ? BuzzKind.thud : BuzzKind.tap,
    );
    if (position.isCheck && !position.isGameOver)
      _sound(BoardSoundKind.check, buzz: BuzzKind.alarm);
    _clearMarks();
    thinking = true;
    _save();
    notifyListeners();
    if (twoPlayers) {
      thinking = false;
      if (isOver) _announce();
      notifyListeners();
      return;
    }
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

  Future<void> _feedback(
    Position before,
    NormalMove move,
    Analysis? beforeAnalysis,
    int token,
  ) async {
    final after = position;
    final engine = await host.engine;
    if (engine == null || isOver) {
      if (engine == null) _engineNotice();
      final tip = tipForMove(before, move, after);
      if (tip != null) _say(tip.text, _toneFor(tip.kind));
      notifyListeners();
      return;
    }
    beforeAnalysis ??= await _analyseSafely(
      () => engine.analyse(before.fen, depth: feedbackDepth),
    );
    final afterAnalysis = await _analyseSafely(
      () => engine.analyse(after.fen, depth: feedbackDepth),
    );
    if (token != _token) return;
    if (beforeAnalysis == null || afterAnalysis == null) {
      final tip = tipForMove(before, move, after);
      if (tip != null) _say(tip.text, _toneFor(tip.kind));
      notifyListeners();
      return;
    }
    evaluation = afterAnalysis.score ?? evaluation;
    final best = beforeAnalysis.bestMove;
    final bestMove = best == null ? null : Move.parse(best);
    final playedBest =
        bestMove != null &&
        before.isLegal(bestMove) &&
        before.play(bestMove).fen == after.fen;
    final quality = classifyMove(
      before: beforeAnalysis.score ?? const Score.cp(0),
      after: afterAnalysis.score ?? const Score.cp(0),
      moverIsWhite: before.turn == Side.white,
      playedBest: playedBest,
    );
    grades[moves.length - 1] = quality;
    if (quality.isError) {
      final why = explainError(
        quality: quality,
        before: before,
        beforeAnalysis: beforeAnalysis,
        after: after,
        afterAnalysis: afterAnalysis,
      );
      final tone = quality == MoveQuality.blunder
          ? CoachTone.error
          : CoachTone.warning;
      _say('${quality.label}. $why', tone);
      _polishLast(why, (text) => '${quality.label}. $text', tone, token);
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
    if (isOver || position.isGameOver) {
      thinking = false;
      notifyListeners();
      return;
    }
    thinking = true;
    notifyListeners();
    final started = DateTime.now();
    NormalMove? chosen;
    if (maia != null && coachElo <= MaiaPlayer.maxElo) {
      try {
        chosen = await maia!.pick(
          [for (final m in moves) m.uci],
          coachElo,
          _rnd,
        );
      } catch (e) {
        debugPrint('Maia failed, using Stockfish: $e');
      }
      if (token != _token || isOver || position.isGameOver) return;
    }
    if (chosen == null) {
      final engine = await host.engine;
      if (engine != null) {
        final a = await _analyseSafely(
          () => engine.analyse(
            position.fen,
            depth: depthForElo(coachElo),
            multiPv: candidatesForElo(coachElo),
          ),
        );
        if (token != _token || isOver || position.isGameOver) return;
        if (a != null) {
          final picked = Move.parse(pickHumanMove(a, coachElo, _rnd));
          if (picked is NormalMove) chosen = picked;
        }
      } else {
        _engineNotice();
      }
    }
    final move = chosen != null && position.isLegal(chosen)
        ? chosen
        : pickPreviewMove(position, _rnd);
    if (move == null) {
      thinking = false;
      notifyListeners();
      return;
    }
    final lastWasError =
        moves.isNotEmpty && (grades[moves.length - 1]?.isError ?? false);
    final wait = Duration(
      milliseconds: 450 + _rnd.nextInt(500) + (lastWasError ? 1500 : 0),
    );
    final elapsed = DateTime.now().difference(started);
    if (elapsed < wait) await Future<void>.delayed(wait - elapsed);
    if (token != _token || isOver || position.isGameOver) return;
    final captured = position.board.pieceAt(move.to);
    _push(move);
    _sound(captured != null ? BoardSoundKind.capture : BoardSoundKind.move);
    if (position.isCheck && !position.isGameOver) _sound(BoardSoundKind.check);
    _clearMarks();
    if (mode == PlayMode.training) {
      final took = captured != null && captured.color == playerSide
          ? ', taking your ${captured.role.name}'
          : '';
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
    if (engine == null || isOver) return;
    final fen = position.fen;
    final a = await _analyseSafely(
      () => engine.analyse(fen, depth: feedbackDepth),
    );
    if (token != _token || position.fen != fen || a == null) return;
    _analysis = a;
    evaluation = a.score ?? evaluation;
    notifyListeners();
  }

  // ---- player tools ----

  Future<void> hint() async {
    if (!playerToMove) return;
    // In a two-player game the coach addresses the side to move by name.
    final turnName = twoPlayers ? '${_name(position.turn)}: ' : '';
    final engine = await host.engine;
    if (engine == null) {
      _ruleHint(turnName);
      return;
    }
    final fen = position.fen;
    final a = _analysis?.fen == fen
        ? _analysis
        : await _analyseSafely(() => engine.analyse(fen, depth: feedbackDepth));
    if (position.fen != fen) return;
    if (a == null || a.bestMove == null) {
      _ruleHint(turnName);
      return;
    }
    _analysis = a;
    final m = Move.parse(a.bestMove!);
    if (m is! NormalMove) return;
    final piece = position.board.pieceAt(m.from);
    if (_hintLevel == 0 && piece != null) {
      highlight = m.from;
      _hintLevel = 1;
      _say(
        'Hint: ${turnName}look at your ${piece.role.name} on ${m.from.name}. Tap Hint again for the move.',
        CoachTone.info,
      );
    } else {
      arrow = m;
      highlight = null;
      _hintLevel = 2;
      _say('Hint: $turnName${sanOf(position, a.bestMove!)}.', CoachTone.info);
    }
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _token++;
    thinking = false;
    if (twoPlayers) {
      // Both sides are human: take back exactly the move that was just played.
      positions.removeLast();
      moves.removeLast();
      sans.removeLast();
      grades.remove(moves.length);
    } else {
      var removedPlayerMove = false;
      while (moves.isNotEmpty &&
          !(removedPlayerMove && position.turn == playerSide)) {
        if (positions.length >= 2 &&
            positions[positions.length - 2].turn == playerSide) {
          removedPlayerMove = true;
        }
        positions.removeLast();
        moves.removeLast();
        sans.removeLast();
        grades.remove(moves.length);
      }
    }
    resigned = false;
    _clearMarks();
    _analysis = null;
    _say(
      'Move taken back. Take your time and check for threats.',
      CoachTone.info,
    );
    _save();
    notifyListeners();
    if (twoPlayers) return;
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

  String _drawReason() {
    if (isThreefoldRepetition) return 'Threefold repetition: the game is a draw.';
    if (isFiftyMoveDraw) return '50-move rule: the game is a draw.';
    if (position.isStalemate) return 'Stalemate: the game is a draw.';
    if (position.isInsufficientMaterial) return 'Insufficient material: the game is a draw.';
    return 'The game is a draw.';
  }

  String _endingReason() {
    if (resigned) return 'resignation';
    if (position.isCheckmate) return 'checkmate';
    if (isThreefoldRepetition) return 'threefold';
    if (isFiftyMoveDraw) return '50-move';
    if (position.isStalemate) return 'stalemate';
    if (position.isInsufficientMaterial) return 'insufficient_material';
    return 'draw';
  }

  void _announce() {
    final p = position;
    if (twoPlayers) {
      // Two humans: just the verdict. No record, no grading, no archive.
      if (resigned) {
        final loser = _name(p.turn);
        _say(
          '$loser resigned. ${_name(p.turn.opposite)} wins.',
          CoachTone.info,
        );
      } else if (p.isCheckmate) {
        _sound(BoardSoundKind.victory);
        _say('Checkmate! ${_name(p.turn.opposite)} wins.', CoachTone.good);
      } else {
        _say(_drawReason(), CoachTone.info);
      }
      _save();
      notifyListeners();
      return;
    }
    final playerWon = !resigned && p.isCheckmate && p.turn != playerSide;
    final playerLost = resigned || p.isCheckmate && p.turn == playerSide;
    if (playerWon) {
      _sound(BoardSoundKind.victory);
    } else if (playerLost) {
      _sound(BoardSoundKind.defeat);
    }
    if (resigned) {
      _say('You resigned. Every lost game is a lesson.', CoachTone.info);
    } else if (p.isCheckmate) {
      p.turn != playerSide
          ? _say('Checkmate! You won. Excellent finish.', CoachTone.good)
          : _say('Checkmate. Let\'s learn from it.', CoachTone.warning);
    } else {
      _say(_drawReason(), CoachTone.info);
    }
    final whiteLost = resigned
        ? playerSide == Side.white
        : p.isCheckmate && p.turn == Side.white;
    final blackLost = resigned
        ? playerSide == Side.black
        : p.isCheckmate && p.turn == Side.black;
    lastRecord = GameRecord(
      id: newId(),
      date: DateTime.now(),
      playerSide: playerSide,
      coachElo: coachElo,
      moves: [for (final m in moves) m.uci],
      result: whiteLost ? '0-1' : (blackLost ? '1-0' : '1/2-1/2'),
      ending: _endingReason(),
      grades: Map.of(grades),
    );
    onFinished?.call(lastRecord!);
    final errors = grades.values.where((q) => q.isError).toList();
    if (grades.isNotEmpty) {
      int count(MoveQuality q) => errors.where((e) => e == q).length;
      _say(
        'Your game: ${count(MoveQuality.blunder)} blunders, ${count(MoveQuality.mistake)} mistakes, '
        '${count(MoveQuality.inaccuracy)} inaccuracies.',
        CoachTone.info,
      );
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

  Future<Analysis?> _analyseSafely(Future<Analysis> Function() analyse) async {
    try {
      return await analyse();
    } catch (e) {
      debugPrint('Stockfish analysis failed: $e');
      _engineNotice(
        'Stockfish had a problem. I will keep the game going with simple advice.',
      );
      return null;
    }
  }

  void _ruleHint(String turnName) {
    for (final m in legalMoves(position)) {
      final piece = freeCapture(position, m);
      if (piece != null) {
        _say(
          'Hint: ${turnName}the ${piece.role.name} on ${m.to.name} is not defended.',
          CoachTone.info,
        );
        notifyListeners();
        return;
      }
    }
    _say(
      'Hint: ${turnName}develop a piece, control the centre or make your king safer.',
      CoachTone.info,
    );
    notifyListeners();
  }

  void _say(String text, CoachTone tone) => chat.add(CoachMessage(text, tone));

  /// Plays a board sound, and the matching phone buzz for the player's own moves.
  void _sound(BoardSoundKind kind, {BuzzKind? buzz}) {
    final s = settings;
    BoardSound.instance.play(kind, soundOn: s?.boardSounds ?? true);
    if (buzz != null)
      BoardSound.instance.buzz(buzz, buzzOn: s?.haptics ?? true);
  }

  /// Replaces the last chat message with the language model's wording when it arrives.
  void _polishLast(
    String facts,
    String Function(String) wrap,
    CoachTone tone,
    int token,
  ) {
    final p = polish;
    if (p == null) return;
    final index = chat.length - 1;
    final original = chat[index];
    unawaited(
      p(facts).then((text) {
        if (text == null ||
            token != _token ||
            index >= chat.length ||
            !identical(chat[index], original))
          return;
        chat[index] = CoachMessage(wrap(text), tone);
        notifyListeners();
      }),
    );
  }

  void _engineNotice([
    String message =
        'Stockfish isn\'t available here, so I\'m using simple rules for now.',
  ]) {
    if (_engineNoticeShown) return;
    _engineNoticeShown = true;
    _say(message, CoachTone.warning);
  }

  void _save() {
    onSave?.call(
      isOver
          ? null
          : jsonEncode({
              'side': playerSide.name,
              'elo': coachElo,
              'mode': mode.name,
              if (twoPlayers) 'two': true,
              'moves': [for (final m in moves) m.uci],
            }),
    );
  }

  static CoachTone _toneFor(TipKind k) => switch (k) {
    TipKind.good => CoachTone.good,
    TipKind.warning => CoachTone.warning,
    TipKind.info => CoachTone.info,
  };

  static String _name(Side s) => s == Side.white ? 'White' : 'Black';

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    super.dispose();
  }
}
