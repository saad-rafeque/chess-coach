import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Enters Android's native picture-in-picture mode for an active game.
class PictureInPicture {
  PictureInPicture._();

  static const _channel = MethodChannel('com.saadrafeque.chess_coach/pip');

  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> enter() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on MissingPluginException {
      // A build without the native Android handler should degrade like an
      // unsupported device, not leave an unhandled exception on the game page.
      return false;
    }
  }
}
