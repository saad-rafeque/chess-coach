import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// Screen refresh rate on Android phones with 90/120 Hz displays. Android runs apps at 60 Hz
/// unless they ask for more, so the app asks for the rate chosen in Settings (the smoothest one by
/// default). Computers always follow the monitor.
class RefreshRate {
  RefreshRate._();

  static bool get adjustable => !kIsWeb && Platform.isAndroid;

  /// The refresh rates the screen offers at its current resolution, lowest first.
  static Future<List<int>> available() async {
    if (!adjustable) return const [];
    try {
      final active = await FlutterDisplayMode.active;
      final rates = {
        for (final m in await FlutterDisplayMode.supported)
          if (m.width == active.width && m.height == active.height) m.refreshRate.round(),
      }.toList()
        ..sort();
      return rates;
    } catch (e) {
      debugPrint('Refresh rates unavailable: $e');
      return const [];
    }
  }

  /// Applies [hz]; 0 means the highest rate the screen offers.
  static Future<void> apply(int hz) async {
    if (!adjustable) return;
    try {
      if (hz <= 0) return await FlutterDisplayMode.setHighRefreshRate();
      final active = await FlutterDisplayMode.active;
      DisplayMode? best;
      for (final m in await FlutterDisplayMode.supported) {
        if (m.width != active.width || m.height != active.height) continue;
        if (best == null || (m.refreshRate - hz).abs() < (best.refreshRate - hz).abs()) best = m;
      }
      if (best != null) await FlutterDisplayMode.setPreferredMode(best);
    } catch (e) {
      debugPrint('Refresh rate not changed: $e');
    }
  }
}
