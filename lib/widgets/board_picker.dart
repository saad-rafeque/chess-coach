import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import 'common.dart';

/// Settings card: a live preview, then the piece sets and boards to choose from.
class BoardPicker extends StatelessWidget {
  const BoardPicker({super.key});

  /// An Italian Game, so every piece shows in the preview.
  static const _previewFen = 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final style = BoardStyle.of(s);
    final themeDefault = BoardStyle.forTheme(s.theme);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, c) {
        final preview = StaticChessboard(
          size: (c.maxWidth < 520 ? c.maxWidth : 260).clamp(160, 360).toDouble(),
          orientation: Side.white,
          fen: _previewFen,
          lastMove: NormalMove.fromUci('g1f3'),
          settings: style.staticSettings(coordinates: s.showCoordinates),
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: preview),
          const SizedBox(height: 16),
          Text('Pieces', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _Strip(children: [
            _PieceTile(
              label: 'Theme',
              assets: themeDefault.pieces,
              selected: s.pieceSet == null || !pieceChoices.containsKey(s.pieceSet),
              onTap: () => s.pieceSet = null,
            ),
            for (final MapEntry(key: id, value: choice) in pieceChoices.entries)
              _PieceTile(
                label: choice.label,
                assets: choice.assets,
                badge: choice.studio ? '3D' : null,
                selected: s.pieceSet == id,
                onTap: () => s.pieceSet = id,
              ),
          ]),
          const SizedBox(height: 16),
          Text('Board', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _Strip(children: [
            _BoardTile(
              label: 'Theme',
              scheme: themeDefault.colors,
              selected: s.boardScheme == null || !boardChoices.containsKey(s.boardScheme),
              onTap: () => s.boardScheme = null,
            ),
            for (final MapEntry(key: id, value: choice) in boardChoices.entries)
              _BoardTile(
                label: choice.label,
                scheme: choice.scheme,
                selected: s.boardScheme == id,
                onTap: () => s.boardScheme = id,
              ),
          ]),
        ]);
      }),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.selected, required this.onTap, required this.child, this.badge});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion(context, const Duration(milliseconds: 160)),
          width: 84,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.14) : p.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? p.accent : p.border, width: selected ? 2 : 1),
          ),
          child: Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: child),
                if (badge != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4)),
                      child: Text(badge!, style: TextStyle(color: p.onAccent, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(color: selected ? p.text : p.muted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _PieceTile extends StatelessWidget {
  const _PieceTile({required this.label, required this.assets, required this.selected, required this.onTap, this.badge});

  final String label;
  final PieceAssets assets;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) => _Tile(
        label: label,
        selected: selected,
        onTap: onTap,
        badge: badge,
        child: Row(children: [
          Expanded(child: Image(image: assets[PieceKind.whiteKnight]!, fit: BoxFit.contain)),
          Expanded(child: Image(image: assets[PieceKind.blackQueen]!, fit: BoxFit.contain)),
        ]),
      );
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.label, required this.scheme, required this.selected, required this.onTap});

  final String label;
  final ChessboardColorScheme scheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Tile(
        label: label,
        selected: selected,
        onTap: onTap,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 64, height: 64, child: scheme.background),
          ),
        ),
      );
}
