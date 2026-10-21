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
    } catch (_) {
      // A build without the native Android handler or on a device with restricted
      // PiP should degrade gracefully, not raise an unhandled exception.
      return false;
    }
  }
}
