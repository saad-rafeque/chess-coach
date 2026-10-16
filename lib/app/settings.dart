import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/event_store.dart';

/// Gives widgets access to [AppSettings] and rebuilds them when it changes.
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child})
      : super(notifier: settings);

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

  /// For callbacks: reads the settings without subscribing to changes.
  static AppSettings read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}

enum AppTheme { light, dark, wooden }

/// User preferences, persisted locally.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs)
      : _theme = AppTheme.values.asNameMap()[_prefs?.getString('theme')] ?? AppTheme.dark,
        _showCoordinates = _prefs?.getBool('coords') ?? true,
        _trainingHints = _prefs?.getBool('hints') ?? true,
        _evalBar = _prefs?.getBool('evalBar') ?? true,
        _coachElo = _prefs?.getInt('coachElo') ?? 800;

  /// In-memory settings for tests.
  AppSettings.memory() : this._(null);

  static Future<AppSettings> load() async {
    return AppSettings._(await SharedPreferences.getInstance());
  }

  final SharedPreferences? _prefs;

  AppTheme _theme;
  AppTheme get theme => _theme;
  set theme(AppTheme value) {
    _theme = value;
    _prefs?.setString('theme', value.name);
    notifyListeners();
  }

  bool _showCoordinates;
  bool get showCoordinates => _showCoordinates;
  set showCoordinates(bool value) {
    _showCoordinates = value;
    _prefs?.setBool('coords', value);
    notifyListeners();
  }

  /// Live coach hints in Training mode.
  bool _trainingHints;
  bool get trainingHints => _trainingHints;
  set trainingHints(bool value) {
    _trainingHints = value;
    _prefs?.setBool('hints', value);
    notifyListeners();
  }

  /// Evaluation bar above the board in Training games.
  bool _evalBar;
  bool get evalBar => _evalBar;
  set evalBar(bool value) {
    _evalBar = value;
    _prefs?.setBool('evalBar', value);
    notifyListeners();
  }

  /// Playing strength of the coach in games.
  int _coachElo;
  int get coachElo => _coachElo;
  set coachElo(int value) {
    _coachElo = value;
    _prefs?.setInt('coachElo', value);
    notifyListeners();
  }

  /// Random id of this install, stamped on stored events (for sync).
  String get deviceId {
    var id = _prefs?.getString('deviceId');
    if (id == null) {
      id = newId();
      _prefs?.setString('deviceId', id);
    }
    return id;
  }

  /// The unfinished game, as JSON (restored on the next start).
  String? get savedGame => _prefs?.getString('savedGame');
  set savedGame(String? value) {
    value == null ? _prefs?.remove('savedGame') : _prefs?.setString('savedGame', value);
  }
}
