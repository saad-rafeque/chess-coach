import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// A board colour scheme the player can pick.
typedef BoardChoice = ({String label, ChessboardColorScheme scheme});

/// A piece set the player can pick.
typedef PieceChoice = ({String label, PieceAssets assets, bool studio});

/// Every board, by the id stored in the settings.
const Map<String, BoardChoice> boardChoices = {
  'brown': (label: 'Brown', scheme: ChessboardColorScheme.brown),
  'wood': (label: 'Wood', scheme: ChessboardColorScheme.wood),
  'wood2': (label: 'Walnut', scheme: ChessboardColorScheme.wood2),
  'wood3': (label: 'Oak', scheme: ChessboardColorScheme.wood3),
  'wood4': (label: 'Light wood', scheme: ChessboardColorScheme.wood4),
  'maple': (label: 'Maple', scheme: ChessboardColorScheme.maple),
  'maple2': (label: 'Maple 2', scheme: ChessboardColorScheme.maple2),
  'leather': (label: 'Leather', scheme: ChessboardColorScheme.leather),
  'marble': (label: 'Marble', scheme: ChessboardColorScheme.marble),
  'blueMarble': (label: 'Blue marble', scheme: ChessboardColorScheme.blueMarble),
  'metal': (label: 'Metal', scheme: ChessboardColorScheme.metal),
  'green': (label: 'Green', scheme: ChessboardColorScheme.green),
  'greenPlastic': (label: 'Green plastic', scheme: ChessboardColorScheme.greenPlastic),
  'olive': (label: 'Olive', scheme: ChessboardColorScheme.olive),
  'blue': (label: 'Blue', scheme: ChessboardColorScheme.blue),
  'blue2': (label: 'Blue 2', scheme: ChessboardColorScheme.blue2),
  'blue3': (label: 'Blue 3', scheme: ChessboardColorScheme.blue3),
  'grey': (label: 'Grey', scheme: ChessboardColorScheme.grey),
  'ic': (label: 'Light blue', scheme: ChessboardColorScheme.ic),
  'canvas': (label: 'Canvas', scheme: ChessboardColorScheme.canvas),
  'purple': (label: 'Purple', scheme: ChessboardColorScheme.purple),
  'purpleDiag': (label: 'Purple stripes', scheme: ChessboardColorScheme.purpleDiag),
  'pinkPyramid': (label: 'Pink', scheme: ChessboardColorScheme.pinkPyramid),
  'newspaper': (label: 'Newspaper', scheme: ChessboardColorScheme.newspaper),
  'horsey': (label: 'Horsey', scheme: ChessboardColorScheme.horsey),
};

/// The app's own 3D Staunton sets (rendered by tool/pieces/staunton.py), by style name.
const studioStyles = <String, String>{};

PieceAssets _studio(String style) => {
      for (final kind in PieceKind.values)
        kind: AssetImage('assets/pieces/$style/${kind.side == Side.white ? 'w' : 'b'}'
            '${kind.role.letter.toUpperCase()}.webp'),
    };

/// Every piece set: the 3D sets first, then the 2D sets that come with the board library.
final Map<String, PieceChoice> pieceChoices = {
  for (final MapEntry(key: style, value: label) in studioStyles.entries)
    'studio-$style': (label: label, assets: _studio(style), studio: true),
  for (final set in PieceSet.values) set.name: (label: set.label, assets: set.assets, studio: false),
};

/// Board colours and piece set: the player's picks, or the theme's defaults.
class BoardStyle {
  const BoardStyle(this.colors, this.pieces);

  final ChessboardColorScheme colors;
  final PieceAssets pieces;

  Color get lightSquare => colors.lightSquare;
  Color get darkSquare => colors.darkSquare;

  static BoardStyle forTheme(AppTheme theme) => switch (theme) {
        AppTheme.light => const BoardStyle(ChessboardColorScheme.blue, PieceSet.cburnettAssets),
        AppTheme.dark => const BoardStyle(ChessboardColorScheme.blue2, PieceSet.cburnettAssets),
        AppTheme.wooden => const BoardStyle(ChessboardColorScheme.wood4, PieceSet.stauntyAssets),
      };

  /// The style for [settings]: chosen board and pieces win over the theme's defaults.
  static BoardStyle of(AppSettings settings) {
    final theme = forTheme(settings.theme);
    return BoardStyle(
      boardChoices[settings.boardScheme]?.scheme ?? theme.colors,
      pieceChoices[settings.pieceSet]?.assets ?? theme.pieces,
    );
  }

  StaticChessboardSettings staticSettings({required bool coordinates}) => StaticChessboardSettings(
        colorScheme: colors,
        pieceAssets: pieces,
        enableCoordinates: coordinates,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      );

  ChessboardSettings settings({required bool coordinates}) => ChessboardSettings(
        colorScheme: colors,
        pieceAssets: pieces,
        enableCoordinates: coordinates,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
        animationDuration: const Duration(milliseconds: 220),
      );
}
