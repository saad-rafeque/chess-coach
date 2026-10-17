import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/event_store.dart';
import 'board_style.dart';

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

/// A name as typed: one line, no control characters, at most 24 characters.
String cleanName(String value) {
  final s = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length > 24 ? s.substring(0, 24).trim() : s;
}

/// The coach plays at 400 to 3200 (see `coachLevels`); anything else is brought into range.
int clampCoachElo(int elo) => elo.clamp(400, 3200);

/// User preferences, persisted locally.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs)
      : _theme = AppTheme.values.asNameMap()[_prefs?.getString('theme')] ?? AppTheme.dark,
        _showCoordinates = _prefs?.getBool('coords') ?? true,
        _trainingHints = _prefs?.getBool('hints') ?? true,
        _evalBar = _prefs?.getBool('evalBar') ?? true,
        _coachElo = clampCoachElo(_prefs?.getInt('coachElo') ?? 800),
        _autoStrength = _prefs?.getBool('autoStrength') ?? true,
        _friendlyVoice = _prefs?.getBool('friendlyVoice') ?? true,
        _panelUnderBoard = _prefs?.getBool('panelUnderBoard') ?? false,
        _boardScheme = _prefs?.getString('boardScheme'),
        _playerName = cleanName(_prefs?.getString('playerName') ?? ''),
        _coachName = cleanName(_prefs?.getString('coachName') ?? ''),
        // Tests start in memory and skip setup; a real install shows it once.
        _onboarded = _prefs?.getBool('onboarded') ?? _prefs == null,
        _pieceSet = _prefs?.getString('pieceSet'),
        _refreshRate = (_prefs?.getInt('refreshRate') ?? 0).clamp(0, 240),
        _voiceModel = _prefs?.getString('voiceModel'),
        _changedAt = DateTime.tryParse(_prefs?.getString('settingsChangedAt') ?? '');

  /// In-memory settings for tests.
  AppSettings.memory() : this._(null);

  static Future<AppSettings> load() async {
    return AppSettings._(await SharedPreferences.getInstance());
  }

  final SharedPreferences? _prefs;
  final _memory = <String, String>{};

  /// When a synced setting last changed on this device (settings sync is last-write-wins).
  DateTime? _changedAt;
  DateTime? get changedAt => _changedAt;

  void _touch() {
    _changedAt = DateTime.now().toUtc();
    _prefs?.setString('settingsChangedAt', _changedAt!.toIso8601String());
  }

  /// The settings shared between devices.
  Map<String, dynamic> toSyncJson() => {
        'theme': _theme.name,
        'coords': _showCoordinates,
        'hints': _trainingHints,
        'evalBar': _evalBar,
        'autoStrength': _autoStrength,
        'coachElo': _coachElo,
        'boardScheme': ?_boardScheme,
        'playerName': _playerName,
        'coachName': _coachName,
        'pieceSet': ?_pieceSet,
      };

  /// Takes the settings from another device if they changed later than ours.
  bool applySync(Map<String, dynamic> j, DateTime changed) {
    if (_changedAt != null && !changed.isAfter(_changedAt!)) return false;
    // Values of the wrong type or out of range (a damaged file) keep what this device has.
    bool flag(String key, bool current) => j[key] is bool ? j[key] as bool : current;
    _theme = AppTheme.values.asNameMap()[j['theme']] ?? _theme;
    _showCoordinates = flag('coords', _showCoordinates);
    _trainingHints = flag('hints', _trainingHints);
    _evalBar = flag('evalBar', _evalBar);
    _autoStrength = flag('autoStrength', _autoStrength);
    if (j['coachElo'] is int) _coachElo = clampCoachElo(j['coachElo'] as int);
    // Only names this version knows (a newer version may offer more; keep ours then).
    String? choice(Object? v, bool Function(String) known, String? current) =>
        v == null ? null : (v is String && known(v) ? v : current);
    _boardScheme = choice(j['boardScheme'], boardChoices.containsKey, _boardScheme);
    if (j['playerName'] is String) _playerName = cleanName(j['playerName'] as String);
    if (j['coachName'] is String) _coachName = cleanName(j['coachName'] as String);
    _pieceSet = choice(j['pieceSet'], pieceChoices.containsKey, _pieceSet);
    _prefs
      ?..setString('theme', _theme.name)
      ..setBool('coords', _showCoordinates)
      ..setBool('hints', _trainingHints)
      ..setBool('evalBar', _evalBar)
      ..setBool('autoStrength', _autoStrength)
      ..setInt('coachElo', _coachElo);
    _boardScheme == null ? _prefs?.remove('boardScheme') : _prefs?.setString('boardScheme', _boardScheme!);
    _pieceSet == null ? _prefs?.remove('pieceSet') : _prefs?.setString('pieceSet', _pieceSet!);
    _prefs
      ?..setString('playerName', _playerName)
      ..setString('coachName', _coachName);
    _changedAt = changed;
    _prefs?.setString('settingsChangedAt', changed.toIso8601String());
    notifyListeners();
    return true;
  }

  /// Small stored values for other services (sync tokens, last sync time).
  String? readValue(String key) => _prefs == null ? _memory[key] : _prefs.getString(key);
  void writeValue(String key, String? value) {
    if (_prefs == null) {
      value == null ? _memory.remove(key) : _memory[key] = value;
    } else {
      value == null ? _prefs.remove(key) : _prefs.setString(key, value);
    }
  }

  AppTheme _theme;
  AppTheme get theme => _theme;
  set theme(AppTheme value) {
    _theme = value;
    _prefs?.setString('theme', value.name);
    _touch();
    notifyListeners();
  }

  bool _showCoordinates;
  bool get showCoordinates => _showCoordinates;
  set showCoordinates(bool value) {
    _showCoordinates = value;
    _prefs?.setBool('coords', value);
    _touch();
    notifyListeners();
  }

  /// Live coach hints in Training mode.
  bool _trainingHints;
  bool get trainingHints => _trainingHints;
  set trainingHints(bool value) {
    _trainingHints = value;
    _prefs?.setBool('hints', value);
    _touch();
    notifyListeners();
  }

  /// Evaluation bar above the board in Training games.
  bool _evalBar;
  bool get evalBar => _evalBar;
  set evalBar(bool value) {
    _evalBar = value;
    _prefs?.setBool('evalBar', value);
    _touch();
    notifyListeners();
  }

  /// Let the skill model pick the coach's strength for each new game.
  bool _autoStrength;
  bool get autoStrength => _autoStrength;
  set autoStrength(bool value) {
    _autoStrength = value;
    _prefs?.setBool('autoStrength', value);
    _touch();
    notifyListeners();
  }

  /// Rephrase coach explanations with the downloaded language model (when one is installed).
  bool _friendlyVoice;
  bool get friendlyVoice => _friendlyVoice;
  set friendlyVoice(bool value) {
    _friendlyVoice = value;
    _prefs?.setBool('friendlyVoice', value);
    notifyListeners();
  }

  /// Chosen board colours and piece set (ids from board_style.dart); null = the theme's default.
  String? _boardScheme;
  String? get boardScheme => _boardScheme;
  set boardScheme(String? value) {
    _boardScheme = value;
    value == null ? _prefs?.remove('boardScheme') : _prefs?.setString('boardScheme', value);
    _touch();
    notifyListeners();
  }

  String? _pieceSet;
  String? get pieceSet => _pieceSet;
  set pieceSet(String? value) {
    _pieceSet = value;
    value == null ? _prefs?.remove('pieceSet') : _prefs?.setString('pieceSet', value);
    _touch();
    notifyListeners();
  }

  /// What the coach calls the player ('' = not given).
  String _playerName;
  String get playerName => _playerName;
  set playerName(String value) {
    _playerName = cleanName(value);
    _prefs?.setString('playerName', _playerName);
    _touch();
    notifyListeners();
  }

  /// The coach's name, chosen at setup.
  String _coachName;
  String get coachName => _coachName.isEmpty ? 'Coach' : _coachName;
  set coachName(String value) {
    _coachName = cleanName(value);
    _prefs?.setString('coachName', _coachName);
    _touch();
    notifyListeners();
  }

  /// First-run setup finished on this device.
  bool _onboarded;
  bool get onboarded => _onboarded;
  set onboarded(bool value) {
    _onboarded = value;
    _prefs?.setBool('onboarded', value);
    notifyListeners();
  }

  /// Phones: keep the coach and puzzle panels under the board instead of behind a button.
  bool _panelUnderBoard;
  bool get panelUnderBoard => _panelUnderBoard;
  set panelUnderBoard(bool value) {
    _panelUnderBoard = value;
    _prefs?.setBool('panelUnderBoard', value);
    notifyListeners();
  }

  /// Phones with fast screens: refresh rate in Hz, 0 = the smoothest the screen offers.
  int _refreshRate;
  int get refreshRate => _refreshRate;
  set refreshRate(int value) {
    _refreshRate = value;
    _prefs?.setInt('refreshRate', value);
    notifyListeners();
  }

  /// Id of the explainer model chosen in Settings (null = the default for this device).
  String? _voiceModel;
  String? get voiceModel => _voiceModel;
  set voiceModel(String? value) {
    _voiceModel = value;
    value == null ? _prefs?.remove('voiceModel') : _prefs?.setString('voiceModel', value);
    notifyListeners();
  }

  /// Playing strength of the coach in games.
  int _coachElo;
  int get coachElo => _coachElo;
  set coachElo(int value) {
    _coachElo = clampCoachElo(value);
    _prefs?.setInt('coachElo', _coachElo);
    _touch();
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
