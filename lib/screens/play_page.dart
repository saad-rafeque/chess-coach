import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show PlatformException;

import '../app/board_style.dart';
import '../app/picture_in_picture.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../coach/coach_player.dart';
import '../coach/llm/coach_voice.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../engine/engine_host.dart';
import '../game/game_controller.dart';
import '../maia/maia_player.dart';
import '../review/guided_review.dart';
import '../train/skill_model.dart';
import '../widgets/board_layout.dart';
import '../widgets/check_pulse.dart';
import '../widgets/common.dart';
import 'review_page.dart';

/// Coach strengths offered in the New game dialog.
const coachLevels = [
  400,
  600,
  800,
  1000,
  1200,
  1400,
  1600,
  1800,
  2000,
  2200,
  2500,
  2800,
  3200,
];

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  final _chatScroll = ScrollController();
  late final ChessboardController _board;
  late final GameController _game;
  bool _flipped = false;
  String _shownFen = '';
  int _chatLength = 0;

  /// Whether the game was over at the last change: the review is offered when a game ends.
  bool _wasOver = false;

  @override
  void initState() {
    super.initState();
    final settings = SettingsScope.read(context);
    final store = StoreScope.read(context);
    _game = GameController(
      host: EngineScope.of(context),
      maia: MaiaPlayer.shared,
      onSave: (json) => settings.savedGame = json,
      onFinished: (r) => store.add(GameRecord.eventType, r.toData(), id: r.id),
      polish: VoiceScope.read(context).polish,
      settings: settings,
    )..hintsEnabled = settings.trainingHints;
    final saved = settings.savedGame;
    if (saved == null || !_game.restore(saved)) {
      _game.newGame(side: Side.white, elo: _strength(settings, store));
    }
    _board = ChessboardController(game: _gameData());
    _shownFen = _game.position.fen;
    _wasOver = _game.isOver;
    _game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    _game.dispose();
    _board.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  GameData _gameData() {
    final pos = _game.position;
    // In a two-player game the side to move is always the "player".
    final side = _game.twoPlayers ? pos.turn : _game.playerSide;
    return GameData(
      fen: pos.fen,
      lastMove: _game.lastMove,
      playerSide: _game.playerToMove
          ? (side == Side.white ? PlayerSide.white : PlayerSide.black)
          : PlayerSide.none,
      sideToMove: pos.turn,
      validMoves: makeLegalMoves(pos),
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _onGameChanged() {
    final fen = _game.position.fen;
    _board.updatePosition(_gameData(), animate: fen != _shownFen);
    _shownFen = fen;
    if (_game.chat.length != _chatLength) {
      _chatLength = _game.chat.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScroll.hasClients) {
          _chatScroll.animateTo(
            _chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
    final record = _game.lastRecord;
    if (_game.isOver &&
        !_game.twoPlayers &&
        !_wasOver &&
        record != null &&
        record.moves.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerReview(record));
    }
    _wasOver = _game.isOver;
    if (mounted) setState(() {});
  }

  /// When a game ends: what would the player like to go through with the coach?
  Future<void> _offerReview(GameRecord record) async {
    if (!mounted) return;
    final coach = SettingsScope.read(context).coachName;
    final focus = await showDialog<ReviewFocus>(
      context: context,
      builder: (context) {
        final p = Palette.of(context);
        return ContentDialog(
          title: Text(switch (record.playerScore) {
            1 => 'You won!',
            0 => 'Game over',
            _ => 'It\'s a draw',
          }),
          constraints: const BoxConstraints(maxWidth: 440),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Go through the game with $coach? Pick what to look at.',
                style: TextStyle(color: p.muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              for (final f in ReviewFocus.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Button(
                    onPressed: () => Navigator.pop(context, f),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.label,
                                  style: TextStyle(
                                    color: p.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  f.detail,
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            FluentIcons.chevron_right,
                            size: 12,
                            color: p.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
          ],
        );
      },
    );
    if (focus != null && mounted)
      await openReview(context, record, focus: focus);
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    if (move is NormalMove) {
      _game.hintsEnabled = SettingsScope.read(context).trainingHints;
      unawaited(_game.playerMove(move));
    }
  }

  /// The coach's strength for a new game: tuned to the player, or the fixed choice.
  int _strength(AppSettings settings, EventStore store) => settings.autoStrength
      ? SkillModel.of(store).recommendedCoachElo
      : settings.coachElo;

  Future<void> _newGameDialog() async {
    final settings = SettingsScope.read(context);
    final recommended = SkillModel.of(
      StoreScope.read(context),
    ).recommendedCoachElo;
    var kind = 'coach';
    var side = 'white';
    var auto = settings.autoStrength;
    var elo = settings.coachElo;
    final start = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => ContentDialog(
          title: const Text('New game'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Opponent'),
              const SizedBox(height: 8),
              Segmented<String>(
                options: const {'coach': 'The coach', 'two': 'Two players'},
                value: kind,
                onChanged: (v) => setDialog(() => kind = v),
              ),
              const SizedBox(height: 16),
              if (kind == 'coach') ...[
                const Text('Play as'),
                const SizedBox(height: 8),
                Segmented<String>(
                  options: const {
                    'white': 'White',
                    'black': 'Black',
                    'random': 'Random',
                  },
                  value: side,
                  onChanged: (v) => setDialog(() => side = v),
                ),
                const SizedBox(height: 16),
                const Text('Coach strength'),
                const SizedBox(height: 8),
                ToggleSwitch(
                  checked: auto,
                  onChanged: (v) => setDialog(() => auto = v),
                  content: SizedBox(
                    width: math.max(
                      100.0,
                      math.min(300.0, MediaQuery.sizeOf(context).width - 140),
                    ),
                    child: const Text('Match my level automatically'),
                  ),
                ),
                const SizedBox(height: 8),
                if (auto)
                  Text(
                    'Your coach plays at about $recommended, so you win a bit less than half of your games. '
                    'It follows your results.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Palette.of(context).muted,
                    ),
                  )
                else ...[
                  ComboBox<int>(
                    value: elo,
                    isExpanded: true,
                    items: [
                      for (final l in coachLevels)
                        ComboBoxItem(
                          value: l,
                          child: Text(
                            l >= 3200
                                ? 'Maximum (Stockfish)'
                                : l <= MaiaPlayer.maxElo
                                ? 'About $l · plays like a human'
                                : 'About $l · Stockfish',
                          ),
                        ),
                    ],
                    onChanged: (v) => setDialog(() => elo = v ?? elo),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Beginners: start around 600–800. Move up when you win most games.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Palette.of(context).muted,
                    ),
                  ),
                ],
              ] else
                Text(
                  'Two people play each other on this device. Pass it over after each move — and '
                  'either player can tap Hint to ask the coach what to play.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Palette.of(context).muted,
                  ),
                ),
            ],
          ),
          actions: [
            Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context, false),
            ),
            FilledButton(
              child: const Text('Start'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (start != true || !mounted) return;
    if (kind == 'two') {
      setState(() => _flipped = false);
      _game.newGame(side: Side.white, elo: settings.coachElo, twoPlayers: true);
      return;
    }
    settings.autoStrength = auto;
    if (auto) {
      elo = recommended;
    } else {
      settings.coachElo = elo;
    }
    final s = side == 'random'
        ? (math.Random().nextBool() ? Side.white : Side.black)
        : Side.values.byName(side);
    setState(() => _flipped = false);
    _game.newGame(side: s, elo: elo);
  }

  Future<void> _enterPictureInPicture() async {
    try {
      final entered = await PictureInPicture.enter();
      if (!entered && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => ContentDialog(
            title: const Text('Picture-in-picture unavailable'),
            content: const Text(
              'This Android version or device does not support picture-in-picture.',
            ),
            actions: [
              Button(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on PlatformException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ContentDialog(
          title: const Text('Could not open the floating board'),
          content: const Text('Keep Chess Coach open and try again.'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final style = BoardStyle.of(s);
    final g = _game;
    final orientation = _flipped ? g.playerSide.opposite : g.playerSide;
    final coachToMove =
        !g.twoPlayers && !g.isOver && g.position.turn != g.playerSide;
    final mat = _calcMaterial(g.position);
    final isWhitePlayer = g.twoPlayers ? true : g.playerSide == Side.white;
    final isBlackPlayer = g.twoPlayers ? true : g.playerSide == Side.black;

    final whiteBar = PlayerBar(
      name: g.twoPlayers
          ? 'White'
          : (isWhitePlayer ? (s.playerName.isEmpty ? 'You' : s.playerName) : s.coachName),
      detail: g.twoPlayers ? 'Player 1' : (isWhitePlayer ? 'White' : '~${g.coachElo}'),
      icon: g.twoPlayers
          ? FluentIcons.contact
          : (isWhitePlayer ? FluentIcons.contact : FluentIcons.robot),
      badge: g.twoPlayers ? null : (isWhitePlayer ? 'YOU' : 'COACH'),
      active: !g.isOver && g.position.turn == Side.white,
      capturedPieces: mat.whiteCaptured,
      advantage: mat.whiteAdvantage,
    );
    final blackBar = PlayerBar(
      name: g.twoPlayers
          ? 'Black'
          : (isBlackPlayer ? (s.playerName.isEmpty ? 'You' : s.playerName) : s.coachName),
      detail: g.twoPlayers ? 'Player 2' : (isBlackPlayer ? 'Black' : '~${g.coachElo}'),
      icon: g.twoPlayers
          ? FluentIcons.contact
          : (isBlackPlayer ? FluentIcons.contact : FluentIcons.robot),
      badge: g.twoPlayers ? null : (isBlackPlayer ? 'YOU' : 'COACH'),
      active: !g.isOver && g.position.turn == Side.black,
      capturedPieces: mat.blackCaptured,
      advantage: mat.blackAdvantage,
    );
    final whiteAtBottom = orientation == Side.white;
    final training = g.mode == PlayMode.training;
    final eval = g.evaluation;
    final latestCoachMessage = g.chat.isEmpty ? null : g.chat.last.text;
    final compactMessage = g.twoPlayers
        ? '${g.position.turn == Side.white ? 'White' : 'Black'} to move'
              '${latestCoachMessage == null ? '' : ' · $latestCoachMessage'}'
        : latestCoachMessage;

    final panel = SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (g.twoPlayers)
            Align(
              alignment: Alignment.centerLeft,
              child: Pill('Two players', color: p.accent),
            )
          else
            Segmented<PlayMode>(
              options: const {
                PlayMode.training: 'Training',
                PlayMode.real: 'Real game',
              },
              value: g.mode,
              onChanged: g.setMode,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                g.twoPlayers ? 'Two players' : s.coachName,
                style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              if (g.thinking && coachToMove)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _EngineStatus(host: EngineScope.of(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              itemCount: g.chat.length,
              itemBuilder: (context, i) => CoachBubble(
                text: g.chat[i].text,
                tone: _bubbleTone(g.chat[i].tone),
              ),
            ),
          ),
          if (g.isOver && !g.twoPlayers && g.lastRecord != null) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => openReview(context, g.lastRecord!),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Review this game'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Moves',
            style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.glassFillSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.glassBorderSubtle),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: g.sans.isEmpty
                  ? Text(
                      'No moves yet',
                      style: TextStyle(color: p.muted, fontSize: 13),
                    )
                  : _MoveList(game: g),
            ),
          ),
        ],
      ),
    );

    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final a in [
          _Action(
            icon: FluentIcons.add,
            label: 'New',
            onPressed: _newGameDialog,
          ),
          _Action(
            icon: FluentIcons.undo,
            label: 'Undo',
            onPressed: g.canUndo ? g.undo : null,
          ),
          _Action(
            icon: FluentIcons.lightbulb,
            label: 'Hint',
            onPressed: (training || g.twoPlayers) && g.playerToMove
                ? g.hint
                : null,
          ),
          _Action(
            icon: FluentIcons.sync,
            label: 'Flip',
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
          _Action(
            icon: FluentIcons.flag,
            label: 'Resign',
            onPressed: g.isOver || g.moves.isEmpty ? null : g.resign,
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            _Action(
              icon: FluentIcons.open_in_new_window,
              label: 'PiP',
              onPressed: _enterPictureInPicture,
            ),
        ])
          Flexible(child: a),
      ],
    );

    final shapes = <Shape>{
      if (g.arrow != null)
        Arrow(
          color: p.success.withValues(alpha: 0.8),
          orig: g.arrow!.from,
          dest: g.arrow!.to,
        ),
      if (g.highlight != null)
        Circle(color: p.accent.withValues(alpha: 0.9), orig: g.highlight!),
    };

    return PageFrame(
      title: 'Play',
      subtitle: isMobile(context)
          ? null
          : 'Play the coach and learn from every move',
      scroll: false,
      compactOnPhone: true,
      child: BoardLayout(
        panelTitle: s.coachName,
        compactMessage: compactMessage,
        compactHint: (training || g.twoPlayers) && g.playerToMove
            ? g.hint
            : null,
        // The coach's latest message stays visible under the board; tapping it opens the panel.
        peek: g.chat.isEmpty
            ? null
            : PeekBubble(
                text: compactMessage ?? g.chat.last.text,
                tone: _bubbleTone(g.chat.last.tone),
              ),
        boardLabel: g.twoPlayers
            ? 'Two players: pass the device after each move. ${g.position.turn == Side.white ? 'White' : 'Black'} to move.'
            : 'Your game against the coach. ${g.playerToMove ? 'Your move' : 'The coach is thinking'}.',
        top: whiteAtBottom ? blackBar : whiteBar,
        bottom: whiteAtBottom ? whiteBar : blackBar,
        overBoard: training && !g.twoPlayers && s.evalBar && eval != null
            ? EvalBar(
                whitePercent: eval.whiteWinPercent,
                label: eval.label,
                flipped: orientation == Side.black,
              )
            : null,
        actions: actions,
        board: (size) => CheckPulse(
          size: size,
          orientation: orientation,
          kingSquare: g.position.isCheck
              ? g.position.board.kingOf(g.position.turn)
              : null,
          child: Chessboard(
            key: const ValueKey('play-board'),
            size: size,
            controller: _board,
            settings: style.settings(coordinates: s.showCoordinates),
            orientation: orientation,
            onMove: _onMove,
            shapes: shapes,
          ),
        ),
        panel: panel,
      ),
    );
  }

  static BubbleTone _bubbleTone(CoachTone t) => switch (t) {
    CoachTone.info => BubbleTone.info,
    CoachTone.good => BubbleTone.good,
    CoachTone.warning || CoachTone.error => BubbleTone.warning,
    CoachTone.move => BubbleTone.move,
  };
}

/// Numbered move list; the player's errors are coloured.
class _MoveList extends StatelessWidget {
  const _MoveList({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Color? colorFor(MoveQuality? q) => switch (q) {
      MoveQuality.inaccuracy => p.warning,
      MoveQuality.mistake => const Color(0xFFF97316),
      MoveQuality.blunder => p.danger,
      _ => null,
    };
    final firstWhite = game.positions.first.turn == Side.white;
    return Text.rich(
      TextSpan(
        style: TextStyle(color: p.text, fontSize: 13, height: 1.5),
        children: [
          for (var i = 0; i < game.sans.length; i++) ...[
            if ((i.isEven) == firstWhite)
              TextSpan(
                text: '${i ~/ 2 + 1}. ',
                style: TextStyle(color: p.muted),
              ),
            TextSpan(
              text:
                  '${game.sans[i]}${game.grades[i] == MoveQuality.blunder
                      ? '??'
                      : game.grades[i] == MoveQuality.mistake
                      ? '?'
                      : game.grades[i] == MoveQuality.inaccuracy
                      ? '?!'
                      : ''}  ',
              style: TextStyle(
                color: colorFor(game.grades[i]),
                fontWeight: game.grades[i] != null && game.grades[i]!.isError
                    ? FontWeight.w600
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EngineStatus extends StatelessWidget {
  const _EngineStatus({required this.host});

  final EngineHost host;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder(
      valueListenable: host.status,
      builder: (context, status, _) => switch (status) {
        EngineStatus.starting => Pill('Starting engine', color: p.muted),
        EngineStatus.ready => Pill('Stockfish', color: p.success),
        EngineStatus.unavailable => Pill('Simple mode', color: p.warning),
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: label,
        child: Button(
          onPressed: onPressed,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (onPressed == null) return p.glassFillSubtle.withValues(alpha: 0.35);
              if (states.isPressed) return p.accent.withValues(alpha: 0.22);
              if (states.isHovered) return p.accent.withValues(alpha: 0.14);
              return p.glassFillSubtle;
            }),
            shape: WidgetStateProperty.resolveWith((states) => RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: states.isHovered && onPressed != null
                    ? p.accent.withValues(alpha: 0.35)
                    : p.glassBorderSubtle,
                width: 1,
              ),
            )),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: isMobile(context) ? 5 : 8,
                vertical: 7,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: onPressed == null
                    ? p.muted.withValues(alpha: 0.45)
                    : p.text,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: onPressed == null
                      ? p.muted.withValues(alpha: 0.45)
                      : p.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialDiff {
  const _MaterialDiff({
    required this.whiteCaptured,
    required this.blackCaptured,
    required this.whiteAdvantage,
    required this.blackAdvantage,
  });

  final List<String> whiteCaptured;
  final List<String> blackCaptured;
  final int whiteAdvantage;
  final int blackAdvantage;
}

_MaterialDiff _calcMaterial(Position pos) {
  var wP = 0, wN = 0, wB = 0, wR = 0, wQ = 0;
  var bP = 0, bN = 0, bB = 0, bR = 0, bQ = 0;

  for (final (_, piece) in pos.board.pieces) {
    if (piece.color == Side.white) {
      switch (piece.role) {
        case Role.pawn:
          wP++;
        case Role.knight:
          wN++;
        case Role.bishop:
          wB++;
        case Role.rook:
          wR++;
        case Role.queen:
          wQ++;
        case Role.king:
          break;
      }
    } else {
      switch (piece.role) {
        case Role.pawn:
          bP++;
        case Role.knight:
          bN++;
        case Role.bishop:
          bB++;
        case Role.rook:
          bR++;
        case Role.queen:
          bQ++;
        case Role.king:
          break;
      }
    }
  }

  final whiteCaptured = <String>[];
  for (var i = 0; i < math.max(0, 8 - bP); i++) {
    whiteCaptured.add('♟');
  }
  for (var i = 0; i < math.max(0, 2 - bN); i++) {
    whiteCaptured.add('♞');
  }
  for (var i = 0; i < math.max(0, 2 - bB); i++) {
    whiteCaptured.add('♝');
  }
  for (var i = 0; i < math.max(0, 2 - bR); i++) {
    whiteCaptured.add('♜');
  }
  for (var i = 0; i < math.max(0, 1 - bQ); i++) {
    whiteCaptured.add('♛');
  }

  final blackCaptured = <String>[];
  for (var i = 0; i < math.max(0, 8 - wP); i++) {
    blackCaptured.add('♙');
  }
  for (var i = 0; i < math.max(0, 2 - wN); i++) {
    blackCaptured.add('♘');
  }
  for (var i = 0; i < math.max(0, 2 - wB); i++) {
    blackCaptured.add('♗');
  }
  for (var i = 0; i < math.max(0, 2 - wR); i++) {
    blackCaptured.add('♖');
  }
  for (var i = 0; i < math.max(0, 1 - wQ); i++) {
    blackCaptured.add('♕');
  }

  final wScore = wP + wN * 3 + wB * 3 + wR * 5 + wQ * 9;
  final bScore = bP + bN * 3 + bB * 3 + bR * 5 + bQ * 9;
  final diff = wScore - bScore;

  return _MaterialDiff(
    whiteCaptured: whiteCaptured,
    blackCaptured: blackCaptured,
    whiteAdvantage: diff > 0 ? diff : 0,
    blackAdvantage: diff < 0 ? -diff : 0,
  );
}
