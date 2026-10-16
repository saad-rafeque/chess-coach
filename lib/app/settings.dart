import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        _trainingHints = _prefs?.getBool('hints') ?? true;

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
}
