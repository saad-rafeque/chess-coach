import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import 'common.dart';

/// Board with player bars on one side and a panel on the other.
///
/// Phones: the board spans the whole screen width, centred on the free space, with the panel
/// behind a slide-up sheet (a slim peek stays under the board when the player chose to keep it
/// there; pages that need the panel, like lessons, keep it right under the board).
/// Desktop: the panel sits beside the board and can be hidden with the dock button, so the
/// board takes the whole window, centred.
class BoardLayout extends StatefulWidget {
  const BoardLayout({
    super.key,
    required this.board,
    required this.panel,
    this.top,
    this.bottom,
    this.actions,
    this.overBoard,
    this.boardLabel,
    this.panelTitle,
    this.peek,
    this.compactMessage,
    this.compactHint,
  });

  final Widget Function(double size) board;
  final Widget panel;
  final Widget? top;
  final Widget? bottom;
  final Widget? actions;

  /// Phones: a compact strip under the board instead of the panel button
  /// (e.g. the coach's latest message); tapping it opens the panel.
  final Widget? peek;

  /// Latest coach text for short split-screen and PiP layouts.
  final String? compactMessage;

  /// Optional primary action beside the coach strip in short layouts.
  final VoidCallback? compactHint;

  /// Slim strip directly above the board (the evaluation bar).
  final Widget? overBoard;

  /// What screen readers announce for the board, e.g. "Puzzle. White to move."
  final String? boardLabel;

  /// Name of the panel's button on phones (e.g. "Coach"). Null keeps the panel under the board.
  final String? panelTitle;

  @override
  State<BoardLayout> createState() => _BoardLayoutState();
}

class _BoardLayoutState extends State<BoardLayout> {
  bool _sheet = false;

  /// Desktop: the side panel is hidden so the board gets the whole window.
  bool _panelHidden = false;

  Widget get panel => widget.panel;
  Widget? get top => widget.top;
  Widget? get bottom => widget.bottom;
  Widget? get actions => widget.actions;
  Widget? get overBoard => widget.overBoard;

  Widget _board(double size) => widget.boardLabel == null
      ? widget.board(size)
      : Semantics(
          container: true,
          label: widget.boardLabel,
          child: widget.board(size),
        );

  static const _barHeight = 44.0;
  static const _overBoardHeight = 14.0;
  static const _panelWidth = 340.0;

  @override
  Widget build(BuildContext context) {
    final underBoard =
        widget.panelTitle == null || SettingsScope.of(context).panelUnderBoard;
    return LayoutBuilder(
      builder: (context, c) {
        final mobile =
            c.maxWidth < mobileBreakpoint || c.maxWidth < c.maxHeight * 0.9;
        final bars =
            (top != null ? _barHeight : 0) +
            (bottom != null ? _barHeight : 0) +
            _overBoardHeight;
        final strip = SizedBox(
          height: _overBoardHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: overBoard ?? const SizedBox.shrink(),
          ),
        );
        // PiP and split-screen windows can be shorter than a phone's normal app view.
        // Keep the board square and as large as fits, with the coach suggestion and
        // a dedicated Hint button directly beneath it. Never derive a negative size.
        if (mobile && c.maxHeight < 430 && widget.panelTitle != null) {
          final footerHeight = math.min(
            52.0,
            math.max(38.0, c.maxHeight * 0.26),
          );
          final p = Palette.of(context);
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, area) {
                        final size = math.max(
                          1.0,
                          math.min(area.maxWidth, area.maxHeight),
                        );
                        return Center(
                          child: SizedBox.square(
                            dimension: size,
                            child: _board(size),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: math.min(footerHeight, c.maxHeight),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: 'Open ${widget.panelTitle} suggestions',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _sheet = true),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: p.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: p.border),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      FluentIcons.robot,
                                      size: 16,
                                      color: p.accent,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      widget.panelTitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.text,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (widget.compactMessage?.isNotEmpty ==
                                        true) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          widget.compactMessage!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: p.muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ] else
                                      const Spacer(),
                                    Icon(
                                      FluentIcons.chevron_up,
                                      size: 12,
                                      color: p.muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.compactHint != null)
                          Button(
                            onPressed: widget.compactHint,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(FluentIcons.lightbulb, size: 15),
                                  SizedBox(width: 5),
                                  Text('Hint'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              ..._sheetOverlay(0, c.maxHeight, compact: true),
            ],
          );
        }
        if (!mobile) {
          // The panel can be hidden so the board gets the whole window and stays centred.
          final p = Palette.of(context);
          final size = _boardSize(
            _panelHidden ? c.maxWidth - 24 : c.maxWidth - _panelWidth - 24,
            c.maxHeight -
                bars -
                30 -
                (_panelHidden && actions != null ? 68 : 0),
          );
          final boardColumn = SizedBox(
            width: size,
            child: Column(
              children: [
                if (top != null) SizedBox(height: _barHeight, child: top),
                SizedBox(
                  height: 28,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: strip),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                          child: Button(
                            style: const ButtonStyle(
                              padding: WidgetStatePropertyAll(
                                EdgeInsets.all(4),
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _panelHidden = !_panelHidden),
                            child: Icon(
                              _panelHidden
                                  ? FluentIcons.dock_right
                                  : FluentIcons.dock_left,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: p.brightness == Brightness.dark
                          ? const Color(0x33FFFFFF)
                          : const Color(0x18000000),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(
                          alpha: p.brightness == Brightness.dark ? 0.45 : 0.16,
                        ),
                        blurRadius: 24,
                        spreadRadius: 1,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _board(size),
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 6),
                  SizedBox(height: _barHeight, child: bottom),
                ],
                if (_panelHidden && actions != null) ...[
                  const SizedBox(height: 12),
                  actions!,
                ],
              ],
            ),
          );
          if (_panelHidden) return Center(child: boardColumn);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              boardColumn,
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: panel),
                    if (actions != null) ...[
                      const SizedBox(height: 12),
                      actions!,
                    ],
                  ],
                ),
              ),
            ],
          );
        }
        // Board pages on phones get the full width from PageFrame; everything except the board keeps a margin.
        final inset = math.max(
          0.0,
          16 - (MediaQuery.sizeOf(context).width - c.maxWidth) / 2,
        );
        Widget padded(Widget w) => inset == 0
            ? w
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: w,
              );
        if (!underBoard) {
          // Phones: the board spans the screen, edge to edge; the panel slides up on request.
          final size = _boardSize(
            c.maxWidth,
            c.maxHeight - bars - (actions != null ? 64 : 0) - 48,
          );
          final content = ListView(
            padding: EdgeInsets.zero,
            children: [
              if (top != null) padded(SizedBox(height: _barHeight, child: top)),
              padded(strip),
              Center(
                child: SizedBox(width: size, height: size, child: _board(size)),
              ),
              if (bottom != null)
                padded(SizedBox(height: _barHeight, child: bottom)),
              if (actions != null) ...[
                const SizedBox(height: 4),
                padded(actions!),
              ],
              const SizedBox(height: 8),
              Center(
                child: Button(
                  onPressed: () => setState(() => _sheet = true),
                  child: widget.peek == null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FluentIcons.chevron_up, size: 12),
                            const SizedBox(width: 8),
                            Text(widget.panelTitle!),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.panelTitle!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            widget.peek!,
                          ],
                        ),
                ),
              ),
            ],
          );
          return Stack(
            children: [
              Positioned.fill(child: content),
              ..._sheetOverlay(inset, c.maxHeight),
            ],
          );
        }
        if (widget.panelTitle == null) {
          // Lessons and review cards need the panel right under the board, no matter the choice.
          final size = _boardSize(
            c.maxWidth,
            c.maxHeight - bars - (actions != null ? 64 : 0) - 72,
          );
          // The panel's minimum grows with the font size, so large text never overflows it.
          final minPanel =
              230.0 * (MediaQuery.textScalerOf(context).scale(14) / 14);
          final panelHeight = math.max(
            minPanel,
            c.maxHeight - size - bars - 76,
          );
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              if (top != null) padded(SizedBox(height: _barHeight, child: top)),
              padded(strip),
              Center(child: _board(size)),
              if (bottom != null)
                padded(SizedBox(height: _barHeight, child: bottom)),
              if (actions != null) ...[
                const SizedBox(height: 4),
                padded(actions!),
              ],
              const SizedBox(height: 12),
              padded(SizedBox(height: panelHeight, child: panel)),
            ],
          );
        }
        // Phones, panel kept under the board: the board sits exactly centred on the screen
        // with a slim panel peek below; tapping the peek slides the full panel up.
        final size = _boardSize(
          c.maxWidth,
          c.maxHeight - bars - (actions != null ? 60 : 0) - 112,
        );
        const peek = 96.0;
        // The screen's bottom bar and page padding are taller than the page header, so the board
        // would sit a little high; this shift puts it on the true centre of the phone screen.
        final topGap = math.max(0.0, c.maxHeight / 2 - bars - size / 2 + 22);
        final content = ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(height: topGap),
            if (top != null) padded(SizedBox(height: _barHeight, child: top)),
            padded(strip),
            Center(child: _board(size)),
            if (bottom != null)
              padded(SizedBox(height: _barHeight, child: bottom)),
            if (actions != null) ...[
              const SizedBox(height: 4),
              padded(actions!),
            ],
            const SizedBox(height: 10),
            padded(
              SizedBox(
                height: peek,
                child: widget.peek == null
                    ? Center(
                        child: Button(
                          onPressed: () => setState(() => _sheet = true),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(FluentIcons.chevron_up, size: 12),
                              const SizedBox(width: 8),
                              Text(widget.panelTitle!),
                            ],
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => setState(() => _sheet = true),
                        child: Center(child: widget.peek!),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
        return Stack(
          children: [
            Positioned.fill(child: content),
            ..._sheetOverlay(inset, c.maxHeight),
          ],
        );
      },
    );
  }

  double _boardSize(double width, double height) =>
      math.max(1.0, math.min(width, height));

  /// The panel as a bottom sheet (phones); it stays part of this page, so it updates live.
  List<Widget> _sheetOverlay(
    double inset,
    double maxHeight, {
    bool compact = false,
  }) {
    final p = Palette.of(context);
    final sheetContent = compact
        ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.panelTitle ?? 'Coach'} suggestion',
                  style: TextStyle(
                    color: p.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.compactMessage?.trim().isNotEmpty == true
                      ? widget.compactMessage!.trim()
                      : 'Ask the coach for a hint when it is your turn.',
                  style: TextStyle(color: p.muted, height: 1.4),
                ),
              ],
            ),
          )
        : panel;
    return [
      IgnorePointer(
        ignoring: !_sheet,
        child: GestureDetector(
          onTap: () => setState(() => _sheet = false),
          child: AnimatedOpacity(
            opacity: _sheet ? 1 : 0,
            duration: motion(context, const Duration(milliseconds: 200)),
            child: Container(color: const Color(0x66000000)),
          ),
        ),
      ),
      AnimatedPositioned(
        duration: motion(context, const Duration(milliseconds: 260)),
        curve: Curves.easeOutCubic,
        left: inset - 16,
        right: inset - 16,
        bottom: _sheet ? -16 : -maxHeight,
        height: maxHeight * 0.75,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 200) setState(() => _sheet = false);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 24),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Close ${widget.panelTitle}',
                    child: GestureDetector(
                      onTap: () => setState(() => _sheet = false),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: p.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: sheetContent),
              ],
            ),
          ),
        ),
      ),
    ];
  }
}

/// Name, rating, captured pieces, and status shown above or below the board.
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.name,
    required this.detail,
    required this.icon,
    this.active = false,
    this.capturedPieces,
    this.advantage,
    this.badge,
    this.clock,
  });

  final String name;
  final String detail;
  final IconData icon;
  final bool active;
  final List<String>? capturedPieces;
  final int? advantage;
  final String? badge;
  final String? clock;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? p.accent.withValues(
                alpha: p.brightness == Brightness.dark ? 0.12 : 0.08,
              )
            : p.surface.withValues(
                alpha: p.brightness == Brightness.dark ? 0.35 : 0.6,
              ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? p.accent.withValues(alpha: 0.35)
              : p.glassBorderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      colors: [
                        p.accent,
                        Color.lerp(p.accent, Colors.white, 0.25)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: active ? null : p.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? p.accent : p.glassBorderSubtle,
                width: 1,
              ),
              boxShadow: [
                if (active)
                  BoxShadow(
                    color: p.accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
              ],
            ),
            child: Icon(
              icon,
              size: 15,
              color: active ? p.onAccent : p.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: p.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: p.accent.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color: p.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.brightness == Brightness.dark
                              ? const Color(0xFFCBD5E1)
                              : p.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((capturedPieces != null && capturedPieces!.isNotEmpty) ||
                    (advantage != null && advantage! > 0)) ...[
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (capturedPieces != null && capturedPieces!.isNotEmpty)
                        Text(
                          capturedPieces!.join(''),
                          style: TextStyle(
                            fontSize: 12,
                            color: p.text.withValues(alpha: 0.85),
                            height: 1.0,
                          ),
                        ),
                      if (advantage != null && advantage! > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+$advantage',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: p.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (clock != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? (p.brightness == Brightness.dark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFF0F172A))
                    : p.glassFillSubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? p.accent : p.glassBorderSubtle,
                  width: active ? 1.5 : 1.0,
                ),
                boxShadow: [
                  if (active)
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.25),
                      blurRadius: 8,
                    ),
                ],
              ),
              child: Text(
                clock!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? (p.brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFFF8FAFC))
                      : p.muted,
                ),
              ),
            )
          else if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: p.accent.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: p.accent,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'to move',
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The colour and icon of a [CoachBubble] tone.
(Color, IconData) bubbleStyle(Palette p, BubbleTone tone) => switch (tone) {
  BubbleTone.info => (p.accent, FluentIcons.chat),
  BubbleTone.good => (p.success, FluentIcons.like),
  BubbleTone.warning => (p.warning, FluentIcons.warning),
  BubbleTone.move => (p.muted, FluentIcons.robot),
};

/// Chat bubble from the coach (or the system).
class CoachBubble extends StatelessWidget {
  const CoachBubble({
    super.key,
    required this.text,
    this.tone = BubbleTone.info,
  });

  final String text;
  final BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = bubbleStyle(p, tone);
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tone == BubbleTone.move ? 0.08 : 0.12),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
          topLeft: Radius.circular(4),
        ),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: p.text, height: 1.35)),
          ),
        ],
      ),
    );
    // New messages fade and slide in (skipped when the system asks for less motion).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, const Duration(milliseconds: 260)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: bubble,
    );
  }
}

enum BubbleTone { info, good, warning, move }

/// One compact chat line for the strip under the board on phones; the whole
/// strip opens the full panel.
class PeekBubble extends StatelessWidget {
  const PeekBubble({
    super.key,
    required this.text,
    this.tone = BubbleTone.info,
  });

  final String text;
  final BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = bubbleStyle(p, tone);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontSize: 13, height: 1.3),
          ),
        ),
        const SizedBox(width: 8),
        Icon(FluentIcons.chevron_up, size: 12, color: p.muted),
      ],
    );
  }
}

/// Thin horizontal bar: White's share of the winning chances.
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.whitePercent,
    required this.label,
    this.flipped = false,
  });

  final double whitePercent;
  final String label;

  /// True when the board shows Black at the bottom (bar fills from the right).
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final share = (whitePercent / 100).clamp(0.02, 0.98);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: const Color(0xFF1E222A)),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    alignment: flipped
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    widthFactor: share,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x33FFFFFF),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: p.glassFillSubtle,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.glassBorderSubtle),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-option segmented switch.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: HoverButton(
                onPressed: () => onChanged(e.key),
                builder: (context, states) => AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: e.key == value ? p.surface : null,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: e.key == value
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF000000,
                              ).withValues(alpha: 0.12),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: e.key == value ? p.text : p.muted,
                      fontWeight: e.key == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
