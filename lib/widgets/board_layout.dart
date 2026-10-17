import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import 'common.dart';

/// Board with player bars on one side and a panel on the other. On phones the board spans the
/// whole screen width and the panel waits behind a button (unless the player chose to keep it under
/// the board, or the page needs it, like lessons).
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
  });

  final Widget Function(double size) board;
  final Widget panel;
  final Widget? top;
  final Widget? bottom;
  final Widget? actions;

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

  Widget get panel => widget.panel;
  Widget? get top => widget.top;
  Widget? get bottom => widget.bottom;
  Widget? get actions => widget.actions;
  Widget? get overBoard => widget.overBoard;

  Widget _board(double size) => widget.boardLabel == null
      ? widget.board(size)
      : Semantics(container: true, label: widget.boardLabel, child: widget.board(size));

  static const _barHeight = 52.0;
  static const _overBoardHeight = 18.0;
  static const _panelWidth = 380.0;

  @override
  Widget build(BuildContext context) {
    final underBoard = widget.panelTitle == null || SettingsScope.of(context).panelUnderBoard;
    return LayoutBuilder(builder: (context, c) {
      final mobile = c.maxWidth < mobileBreakpoint || c.maxWidth < c.maxHeight * 0.9;
      final bars = (top != null ? _barHeight : 0) + (bottom != null ? _barHeight : 0) + _overBoardHeight;
      final strip = SizedBox(
        height: _overBoardHeight,
        child: Align(alignment: Alignment.topCenter, child: overBoard ?? const SizedBox.shrink()),
      );
      if (!mobile) {
        final size = math.min(c.maxWidth - _panelWidth - 24, c.maxHeight - bars);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: size,
              child: Column(children: [
                if (top != null) SizedBox(height: _barHeight, child: top),
                strip,
                _board(size),
                if (bottom != null) SizedBox(height: _barHeight, child: bottom),
              ]),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: panel), if (actions != null) ...[const SizedBox(height: 12), actions!]],
              ),
            ),
          ],
        );
      }
      final p = Palette.of(context);
      // Board pages on phones get the full width from PageFrame; everything except the board keeps a margin.
      final inset = math.max(0.0, 16 - (MediaQuery.sizeOf(context).width - c.maxWidth) / 2);
      Widget padded(Widget w) => inset == 0 ? w : Padding(padding: EdgeInsets.symmetric(horizontal: inset), child: w);
      if (!underBoard) {
        // Phones: the board spans the screen, edge to edge; the panel slides up on request.
        final size = math.max(160.0, math.min(c.maxWidth, c.maxHeight - bars - (actions != null ? 64 : 0) - 56));
        final content = ListView(
          padding: EdgeInsets.zero,
          children: [
            if (top != null) padded(SizedBox(height: _barHeight, child: top)),
            padded(strip),
            Center(child: SizedBox(width: size, height: size, child: _board(size))),
            if (bottom != null) padded(SizedBox(height: _barHeight, child: bottom)),
            if (actions != null) ...[const SizedBox(height: 4), padded(actions!)],
            const SizedBox(height: 8),
            Center(
              child: Button(
                onPressed: () => setState(() => _sheet = true),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(FluentIcons.chevron_up, size: 12),
                  const SizedBox(width: 8),
                  Text(widget.panelTitle!),
                ]),
              ),
            ),
          ],
        );
        return Stack(children: [
          Positioned.fill(child: content),
          // The panel as a sheet; it stays part of this page, so it updates live.
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
            bottom: _sheet ? -16 : -c.maxHeight,
            height: c.maxHeight * 0.75,
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 200) setState(() => _sheet = false);
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: p.background,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                          decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: panel),
                ]),
              ),
            ),
          ),
        ]);
      }
      // Phones, panel kept under the board: everything below the board scrolls.
      final size = math.min(c.maxWidth, c.maxHeight * 0.62 - bars);
      final panelHeight = math.max(320.0, c.maxHeight - size - bars - 76);
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          if (top != null) padded(SizedBox(height: _barHeight, child: top)),
          padded(strip),
          Center(child: _board(size)),
          if (bottom != null) padded(SizedBox(height: _barHeight, child: bottom)),
          if (actions != null) ...[const SizedBox(height: 4), padded(actions!)],
          const SizedBox(height: 12),
          padded(SizedBox(height: panelHeight, child: panel)),
        ],
      );
    });
  }
}

/// Name, rating and status shown above or below the board.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.name, required this.detail, required this.icon, this.active = false});

  final String name;
  final String detail;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: active ? p.accent : p.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: active ? p.onAccent : p.muted),
      ),
      const SizedBox(width: 10),
      Text(name, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
      ),
      if (active)
        Text('to move', style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Chat bubble from the coach (or the system).
class CoachBubble extends StatelessWidget {
  const CoachBubble({super.key, required this.text, this.tone = BubbleTone.info});

  final String text;
  final BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = switch (tone) {
      BubbleTone.info => (p.accent, FluentIcons.chat),
      BubbleTone.good => (p.success, FluentIcons.like),
      BubbleTone.warning => (p.warning, FluentIcons.warning),
      BubbleTone.move => (p.muted, FluentIcons.robot),
    };
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
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: p.text, height: 1.35))),
      ]),
    );
    // New messages fade and slide in (skipped when the system asks for less motion).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, const Duration(milliseconds: 260)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: bubble,
    );
  }
}

enum BubbleTone { info, good, warning, move }

/// Thin horizontal bar: White's share of the winning chances.
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.whitePercent, required this.label, this.flipped = false});

  final double whitePercent;
  final String label;

  /// True when the board shows Black at the bottom (bar fills from the right).
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final share = (whitePercent / 100).clamp(0.02, 0.98);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(children: [
              Container(color: const Color(0xFF2B2B2E)),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                alignment: flipped ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: share,
                child: Container(color: const Color(0xFFF2F2F2)),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 42,
        child: Text(label,
            textAlign: TextAlign.right,
            style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Two-option segmented switch.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
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
                      ? [BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0.12), blurRadius: 6)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                    style: TextStyle(
                        color: e.key == value ? p.text : p.muted,
                        fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w400)),
              ),
            ),
          ),
      ]),
    );
  }
}
