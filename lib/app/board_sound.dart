import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The five wooden board sounds, played from `assets/sounds/`.
enum BoardSoundKind { move, capture, check, victory, defeat }

/// Phone vibrations that go with the sounds: light for a move, medium for a
/// capture, heavy for a check.
enum BuzzKind { tap, thud, alarm }

/// Plays the wooden piece sounds and the matching phone vibrations.
///
/// Everything is best-effort: when the audio device or the vibration service
/// is unavailable (headless tests, some Linux setups) the calls fail silently,
/// so games, puzzles and lessons never break because of a missing sound.
class BoardSound {
  BoardSound._();

  static final BoardSound instance = BoardSound._();

  /// True under `flutter test`, where no audio plugin is registered:
  /// constructing an [AudioPlayer] there would raise an unhandled
  /// MissingPluginException, so the service stays fully silent instead.
  static final bool _inTests = Platform.environment['FLUTTER_TEST'] == 'true';

  /// Piece sounds (moves and captures) share one player so they queue nicely;
  /// louder events (check, game end) use another and can cut in.
  AudioPlayer? _pieces;
  AudioPlayer? _events;

  static const _paths = {
    BoardSoundKind.move: 'sounds/move.mp3',
    BoardSoundKind.capture: 'sounds/capture.mp3',
    BoardSoundKind.check: 'sounds/check.mp3',
    BoardSoundKind.victory: 'sounds/victory.mp3',
    BoardSoundKind.defeat: 'sounds/defeat.mp3',
  };

  /// Plays [kind] when board sounds are on. Never throws.
  void play(BoardSoundKind kind, {required bool soundOn}) {
    if (!soundOn || _inTests) return;
    final path = _paths[kind];
    if (path == null) return;
    try {
      final player = switch (kind) {
        BoardSoundKind.move || BoardSoundKind.capture => _pieces ??= AudioPlayer(),
        _ => _events ??= AudioPlayer(),
      };
      unawaited(player.play(AssetSource(path)).catchError((Object e) => _quiet(e)));
    } catch (e) {
      _quiet(e);
    }
  }

  /// A short vibration when haptics are on (phones only). Never throws.
  void buzz(BuzzKind kind, {required bool buzzOn}) {
    if (!buzzOn || _inTests || !Platform.isAndroid && !Platform.isIOS) return;
    final Future<void> call;
    try {
      call = switch (kind) {
        BuzzKind.tap => HapticFeedback.lightImpact(),
        BuzzKind.thud => HapticFeedback.mediumImpact(),
        BuzzKind.alarm => HapticFeedback.heavyImpact(),
      };
    } catch (_) {
      // No vibration service: stay quiet.
      return;
    }
    unawaited(call.catchError((_) {}));
  }

  static void _quiet(Object e) {
    // A missing audio plugin is normal in tests and on machines without audio.
    if (e is! MissingPluginException) debugPrint('Board sound unavailable: $e');
  }
}
