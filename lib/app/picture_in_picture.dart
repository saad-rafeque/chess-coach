import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native PiP state is explicit: a short split-screen window is still interactive.
class PictureInPicture {
  PictureInPicture._();
  static const _channel = MethodChannel('com.saadrafeque.chess_coach/pip');
  static final active = ValueNotifier<bool>(false);
  static final hints = ValueNotifier<int>(0);
  static final undoRequests = ValueNotifier<int>(0);
  static final playHintRequests = ValueNotifier<int>(0);
  static bool _initialized = false;

  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'modeChanged') active.value = call.arguments == true;
      if (call.method == 'hint') hints.value++;
      if (call.method == 'undo') undoRequests.value++;
      if (call.method == 'playHint') playHintRequests.value++;
    });
  }

  static Future<void> setHintAvailable(bool available) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('hintAvailable', available);
    } catch (_) {
      /* Older builds may not expose PiP actions. */
    }
  }

  /// Android PiP windows do not forward taps to the board. These system actions
  /// let the player request guidance, play a revealed hint, or take a move back.
  static Future<void> setActionsAvailable({
    required bool hint,
    required bool undo,
    required bool playHint,
  }) async {
    if (!supported) return;
    initialize();
    try {
      await _channel.invokeMethod<void>('actionsAvailable', {
        'hint': hint,
        'undo': undo,
        'playHint': playHint,
      });
    } catch (_) {
      // Retain hints when running against an older Android host.
      await setHintAvailable(hint);
    }
  }

  static Future<bool> enter() async {
    if (!supported) return false;
    initialize();
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }
}
