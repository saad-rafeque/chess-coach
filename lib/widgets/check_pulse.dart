import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';

/// The red of the check glow.
const _glow = Color(0xFFFF3B30);

/// The board square that holds [square], in the board's own coordinates
/// (the same layout chessground paints: file x from the left, rank 7 at top).
Offset _squareOrigin(Square square, double squareSize, Side orientation) {
  final x = orientation == Side.black ? 7 - square.file : square.file;
  final y = orientation == Side.black ? square.rank : 7 - square.rank;
  return Offset(x * squareSize, y * squareSize);
}

/// A red pulse on the king's square while the side to move is in check.
///
/// Layered over the board ([child]) and aligned with its squares, on top of
/// the board's own check tint; taps pass through to the board. With reduced
/// motion the glow is static. The square math assumes the borderless boards
/// this app uses.
class CheckPulse extends StatefulWidget {
  const CheckPulse({
    super.key,
    required this.size,
    required this.orientation,
    required this.kingSquare,
    this.child,
  });

  /// Board size, the same value given to [Chessboard].
  final double size;

  /// Side the board is oriented towards, the same as [Chessboard.orientation].
  final Side orientation;

  /// The checked king's square; null shows nothing.
  final Square? kingSquare;

  /// The board itself.
  final Widget? child;

  @override
  State<CheckPulse> createState() => _CheckPulseState();
}

class _CheckPulseState extends State<CheckPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    if (reduced) {
      _pulse.stop();
      _pulse.value = 0.5;
    } else if (widget.kingSquare != null) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(CheckPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.kingSquare == oldWidget.kingSquare) return;
    if (widget.kingSquare == null) {
      _pulse.stop();
    } else if (!_reducedMotion) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final king = widget.kingSquare;
    final squareSize = widget.size / 8;
    final origin = king == null ? Offset.zero : _squareOrigin(king, squareSize, widget.orientation);
    return Stack(children: [
      widget.child ?? const SizedBox.shrink(),
      if (king != null)
        Positioned(
          left: origin.dx,
          top: origin.dy,
          width: squareSize,
          height: squareSize,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _reducedMotion ? 0.5 : 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
                return Container(
                  decoration: BoxDecoration(
                    color: _glow.withValues(alpha: 0.08 + 0.22 * t),
                    border: Border.all(color: _glow.withValues(alpha: 0.30 + 0.55 * t), width: 2.5),
                  ),
                );
              },
            ),
          ),
        ),
    ]);
  }
}
