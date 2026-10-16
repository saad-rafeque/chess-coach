import 'package:chessground/chessground.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// Board colours and piece set for each app theme.
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
