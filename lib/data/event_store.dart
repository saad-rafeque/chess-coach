import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'data_folder.dart';
import 'event_validation.dart';

/// One immutable record: a finished game, a puzzle attempt, a lesson step...
/// Events are only ever added, so copies from different devices merge by id.
class AppEvent {
  const AppEvent({
    required this.id,
    required this.type,
    required this.time,
    required this.device,
    required this.data,
  });

  factory AppEvent.fromJson(Map<String, dynamic> j) => AppEvent(
    id: j['id'] as String,
    type: j['type'] as String,
    time: DateTime.parse(j['time'] as String),
    device: j['device'] as String? ?? '',
    data: (j['data'] as Map).cast<String, dynamic>(),
  );

  final String id;
  final String type;
  final DateTime time;
  final String device;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'time': time.toUtc().toIso8601String(),
    'device': device,
    'data': data,
  };
}

String newId([math.Random? rnd]) {
  final r = rnd ?? math.Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Append-only log of [AppEvent]s in a JSON-lines file.
class EventStore extends ChangeNotifier {
  EventStore._(this._file, this.device);

  /// In-memory store for tests.
  EventStore.memory({this.device = 'test'}) : _file = null;

  static Future<EventStore> open({required String device}) async {
    final dir = await dataFolder();
    return openFile(
      File('${dir.path}${Platform.pathSeparator}events.jsonl'),
      device: device,
    );
  }

  static Future<EventStore> openFile(
    File file, {
    required String device,
  }) async {
    final store = EventStore._(file, device);
    try {
      await secureDataFile(file);
    } catch (_) {
      store.storageError =
          'Your progress cannot be opened safely on this device.';
      return store;
    }
    await store._load();
    return store;
  }

  final File? _file;
  final String device;
  final _events = <AppEvent>[];
  final _ids = <String>{};

  List<AppEvent> get events => List.unmodifiable(_events);

  /// Set when progress can't be saved (no storage, disk full...). The app keeps working in memory.
  String? storageError;

  Future<void> _append(String text) async {
    final f = _file;
    if (f == null) return;
    try {
      await secureDataFile(f);
      await f.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (e) {
      storageError = 'Your progress could not be saved on this device ($e).';
    }
  }

  Iterable<AppEvent> ofType(String type) =>
      _events.where((e) => e.type == type);

  static int _compare(AppEvent a, AppEvent b) {
    final c = a.time.compareTo(b.time);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  Future<void> _load() async {
    final f = _file;
    if (f == null || !f.existsSync()) return;
    if (await f.length() > 128 * 1024 * 1024) {
      storageError = 'Event history file exceeds safe limits.';
      return;
    }
    var skipped = 0;
    try {
      final lines = f
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        if (line.length > maxEventChars * 2) {
          skipped++;
          continue;
        }
        AppEvent? e;
        try {
          e = parseEvent(jsonDecode(line));
        } catch (_) {}
        if (e == null) {
          skipped++;
        } else {
          _insert(e);
        }
      }
    } catch (e) {
      debugPrint('Error reading event log: $e');
    }
    if (skipped > 0) debugPrint('Skipped $skipped damaged event lines');
  }

  bool _insert(AppEvent e) {
    if (!_ids.add(e.id)) return false;
    // New events usually come last; only older ones (from sync) need a search.
    if (_events.isEmpty || _compare(_events.last, e) <= 0) {
      _events.add(e);
      return true;
    }
    final i = _events.indexWhere((x) => _compare(x, e) > 0);
    if (i == -1) {
      _events.add(e);
    } else {
      _events.insert(i, e);
    }
    return true;
  }

  Future<AppEvent> add(
    String type,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final e = AppEvent(
      id: id ?? newId(),
      type: type,
      time: DateTime.now().toUtc(),
      device: device,
      data: data,
    );
    if (_insert(e)) {
      await _append('${jsonEncode(e.toJson())}\n');
      notifyListeners();
    }
    return e;
  }

  /// Adds events from another copy of the log (sync). Returns how many were new.
  /// Events that fail [isValidEvent] are left out.
  Future<int> merge(Iterable<AppEvent> incoming) async {
    final fresh = [
      for (final e in incoming)
        if (isValidEvent(e) && _insert(e)) e,
    ];
    if (fresh.isNotEmpty) {
      await _append(fresh.map((e) => '${jsonEncode(e.toJson())}\n').join());
      notifyListeners();
    }
    return fresh.length;
  }
}

/// Gives widgets the app's [EventStore]; they rebuild when events are added.
class StoreScope extends InheritedNotifier<EventStore> {
  const StoreScope({super.key, required EventStore store, required super.child})
    : super(notifier: store);

  static EventStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  static EventStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
