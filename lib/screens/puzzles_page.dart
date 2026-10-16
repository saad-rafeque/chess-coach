import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../data/event_store.dart';
import '../puzzles/mistakes.dart';
import '../puzzles/puzzle.dart';
import '../widgets/board_layout.dart';
import '../widgets/common.dart';

enum PuzzleMode { rated, themes, mistakes }

const _themeChoices = [
  'mateIn1', 'mateIn2', 'fork', 'pin', 'skewer', 'hangingPiece', 'discoveredAttack', 'backRankMate',
  'trappedPiece', 'sacrifice', 'promotion', 'endgame', 'opening', 'defensiveMove',
];

/// Opens a short puzzle drill (from a training session). Returns how many puzzles were tried.
Future<int?> openPuzzleDrill(BuildContext context, {required int goal, String? theme}) => Navigator.of(context)
    .push<int>(FluentPageRoute(builder: (_) => PuzzlesPage(goal: goal, theme: theme)));

class PuzzlesPage extends StatefulWidget {
  const PuzzlesPage({super.key, this.bank, this.goal, this.theme});

  /// Puzzle set; null loads the bundled one.
  final Future<PuzzleBank>? bank;

  /// Drill mode: number of puzzles to do, shown as a pushed page with a back button.
  final int? goal;

  /// Drill mode: puzzle theme (null = rated puzzles).
  final String? theme;

  @override
  State<PuzzlesPage> createState() => _PuzzlesPageState();
}

class _PuzzlesPageState extends State<PuzzlesPage> {
  final _rnd = math.Random();
  PuzzleBank? _bank;
  String? _loadError;
  PuzzleSession? _session;
  late final ChessboardController _board;
  PuzzleMode _mode = PuzzleMode.rated;
  String _theme = 'fork';
  double? _ratingBefore;
  String _shownFen = '';

  /// Puzzles tried on this page (drill progress).
  int _tried = 0;

  bool get _drill => widget.goal != null;
  bool get _drillDone => _drill && _tried >= widget.goal!;

  @override
  void initState() {
    super.initState();
    if (widget.theme != null) {
      _mode = PuzzleMode.themes;
      _theme = widget.theme!;
    }
    _board = ChessboardController(game: _emptyGame());
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final bank = await (widget.bank ?? PuzzleBank.shared());
      if (!mounted) return;
      setState(() => _bank = bank);
      _nextPuzzle();
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Puzzles could not be loaded ($e).');
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    _board.dispose();
    super.dispose();
  }

  GameData _emptyGame() => GameData(
        fen: Chess.initial.fen,
        playerSide: PlayerSide.none,
        sideToMove: Side.white,
        validMoves: const {},
      );

  GameData _gameData(PuzzleSession s) {
    final pos = s.position;
    final canMove = s.state == PuzzleState.playerToMove || s.state == PuzzleState.wrongMove;
    return GameData(
      fen: pos.fen,
      lastMove: s.lastMove,
      playerSide: canMove ? (s.playerSide == Side.white ? PlayerSide.white : PlayerSide.black) : PlayerSide.none,
      sideToMove: pos.turn,
      validMoves: canMove ? makeLegalMoves(pos) : const {},
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _onSession() {
    final s = _session!;
    final fen = s.position.fen;
    _board.updatePosition(_gameData(s), animate: fen != _shownFen);
    _shownFen = fen;
    if (mounted) setState(() {});
  }

  void _nextPuzzle() {
    final bank = _bank;
    if (bank == null) return;
    final store = StoreScope.read(context);
    final stats = PuzzleStats.fromEvents(store.events);
    PuzzleItem? next;
    if (_mode == PuzzleMode.mistakes) {
      final mine = mistakePuzzles(store);
      final fresh = mine.where((p) => !stats.seen.contains(p.id)).toList();
      final pool = fresh.isNotEmpty ? fresh : mine;
      next = pool.isEmpty ? null : pool[_rnd.nextInt(pool.length)];
    } else {
      next = bank.next(
        rating: stats.rating.rating,
        theme: _mode == PuzzleMode.themes ? _theme : null,
        exclude: stats.seen,
        random: _rnd,
      );
    }
    _session?.removeListener(_onSession);
    _session?.dispose();
    _session = null;
    _ratingBefore = stats.rating.rating;
    if (next == null) {
      _board.updatePosition(_emptyGame(), animate: false);
      setState(() {});
      return;
    }
    final session = PuzzleSession(next, onResult: (p, solved) {
      if (mounted) setState(() => _tried++);
      store.add(puzzleEventType, {
        'id': p.id,
        'solved': solved,
        'puzzleRating': p.rating,
        'themes': p.themes,
        'rated': p.setup,
      });
    });
    _session = session..addListener(_onSession);
    _shownFen = session.position.fen;
    _board.updatePosition(_gameData(session), animate: false, resetPremove: true);
    setState(() {});
    unawaited(session.start());
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final s = _session;
    if (s == null || move is! NormalMove) return;
    unawaited(s.playerMove(move).then((ok) {
      if (!ok && mounted) _board.updatePosition(_gameData(s), animate: false);
    }));
  }

  void _setMode(PuzzleMode m) {
    setState(() => _mode = m);
    _nextPuzzle();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final store = StoreScope.of(context);
    final stats = PuzzleStats.fromEvents(store.events);
    final style = BoardStyle.forTheme(s.theme);
    final session = _session;
    final mistakesCount = _bank == null ? 0 : mistakePuzzles(store).length;

    final ratingPill = Pill('Rating ${stats.rating.rating.round()}', color: p.accent);
    final drillTitle = widget.theme == null ? 'Puzzles' : '${themeNames[widget.theme] ?? 'Themed'} puzzles';
    return PageFrame(
      title: _drill ? drillTitle : 'Puzzles',
      subtitle: _drill
          ? '${_tried.clamp(0, widget.goal!)} of ${widget.goal} done'
          : (isMobile(context) ? null : 'Sharpen your tactics, a few minutes at a time'),
      leading: _drill
          ? IconButton(
              icon: const Icon(FluentIcons.back, size: 18),
              onPressed: () => Navigator.of(context).pop(_tried),
            )
          : null,
      trailing: ratingPill,
      scroll: false,
      child: BoardLayout(
        board: (size) => Chessboard(
          size: size,
          controller: _board,
          settings: style.settings(coordinates: s.showCoordinates),
          orientation: session?.playerSide ?? Side.white,
          onMove: _onMove,
          shapes: {
            if (session?.hintSquare != null) Circle(color: p.accent.withValues(alpha: 0.9), orig: session!.hintSquare!),
          },
        ),
        panel: SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: ListView(children: [
            if (_drill) ...[
              Meter(_tried / widget.goal!),
              if (_drillDone) ...[
                const SizedBox(height: 12),
                const CoachBubble(text: 'Drill complete! Go back to your session, or keep solving.', tone: BubbleTone.good),
                FilledButton(onPressed: () => Navigator.of(context).pop(_tried), child: const Text('Back to session')),
              ],
            ] else
              Segmented<PuzzleMode>(
                options: {
                  PuzzleMode.rated: 'Rated',
                  PuzzleMode.themes: 'Themes',
                  PuzzleMode.mistakes: 'Mistakes${mistakesCount > 0 ? ' ($mistakesCount)' : ''}',
                },
                value: _mode,
                onChanged: _setMode,
              ),
            if (_mode == PuzzleMode.themes && !_drill) ...[
              const SizedBox(height: 12),
              ComboBox<String>(
                value: _theme,
                isExpanded: true,
                items: [for (final t in _themeChoices) ComboBoxItem(value: t, child: Text(themeNames[t]!))],
                onChanged: (t) {
                  if (t == null) return;
                  setState(() => _theme = t);
                  _nextPuzzle();
                },
              ),
            ],
            const SizedBox(height: 16),
            ..._status(p, session, stats),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _MiniStat(label: 'Rating', value: '${stats.rating.rating.round()}')),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat(label: 'Solved', value: '${stats.solved}')),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat(label: 'Streak', value: '${stats.streakDays} d')),
            ]),
          ]),
        ),
        actions: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          Button(
            onPressed: session == null || session.finished ? null : session.hint,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(FluentIcons.lightbulb, size: 14),
              SizedBox(width: 6),
              Text('Hint'),
            ]),
          ),
          Button(
            onPressed: session == null || session.finished ? null : session.showSolution,
            child: const Text('Solution'),
          ),
          FilledButton(
            onPressed: _bank == null ? null : _nextPuzzle,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Next puzzle'),
              SizedBox(width: 6),
              Icon(FluentIcons.chevron_right, size: 12),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _status(Palette p, PuzzleSession? session, PuzzleStats stats) {
    if (_loadError != null) return [CoachBubble(text: _loadError!, tone: BubbleTone.warning)];
    if (_bank == null) {
      return [
        Row(children: [
          Icon(FluentIcons.puzzle, size: 16, color: p.muted),
          const SizedBox(width: 10),
          Text('Loading puzzles…', style: TextStyle(color: p.muted)),
        ]),
      ];
    }
    if (session == null) {
      return [
        CoachBubble(
          text: _mode == PuzzleMode.mistakes
              ? 'No mistake puzzles yet. Play a game and open its review: your mistakes become puzzles here.'
              : 'No puzzle found for this choice.',
          tone: BubbleTone.info,
        ),
      ];
    }
    final side = session.playerSide == Side.white ? 'White' : 'Black';
    final change = stats.rating.rating - (_ratingBefore ?? stats.rating.rating);
    final changeText = session.puzzle.setup && change.abs() >= 1
        ? ' (${change > 0 ? '+' : ''}${change.round()} rating)'
        : '';
    final (text, tone) = switch (session.state) {
      PuzzleState.opponentMoving => ('Watch your opponent\'s move…', BubbleTone.move),
      PuzzleState.playerToMove => (
          session.puzzle.setup ? 'Your turn: find the best move for $side.' : 'You went wrong here in a game. Find the best move for $side.',
          BubbleTone.info
        ),
      PuzzleState.wrongMove => ('Not the best move. Look for checks, captures and threats, then try again.', BubbleTone.warning),
      PuzzleState.solved => ('Solved!$changeText', BubbleTone.good),
      PuzzleState.showingSolution => ('Here is the solution.$changeText', BubbleTone.move),
    };
    return [
      Text('$side to move', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      CoachBubble(text: text, tone: tone),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Pill('Puzzle ${session.puzzle.rating}', color: p.muted),
        if (session.finished)
          for (final t in session.puzzle.namedThemes.take(3)) Pill(t),
      ]),
    ];
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
      ]),
    );
  }
}
