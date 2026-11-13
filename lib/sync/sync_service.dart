import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/settings.dart';
import '../data/event_store.dart';
import 'drive.dart';
import 'google_auth.dart';
import 'play_services_auth.dart';
import 'token_store.dart';

enum SyncStatus {
  notSetUp,
  signedOut,
  signingIn,
  disconnecting,
  idle,
  syncing,
  offline,
  error,
}

/// Merges per-installation snapshots in the user's private Google Drive app folder.
///
/// Battery-friendly by design: it syncs when the app opens or comes back, when it is
/// closed or sent to the background, and (only after a failed attempt) retries a few
/// times with growing pauses until the network returns. No polling otherwise.
/// Events merge as a union by id, so nothing is ever overwritten; settings are
/// last-write-wins.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService({
    required this.store,
    required this.settings,
    this.config = OAuthConfig.fromEnvironment,
    GoogleAuth? auth,
    SyncFolder Function(Future<String> Function() token)? folder,
    Future<bool> Function(Uri url)? openBrowser,
    TokenStore? tokens,
    this.retryDelays = const [
      Duration(minutes: 1),
      Duration(minutes: 3),
      Duration(minutes: 10),
      Duration(minutes: 30),
    ],
  }) : auth =
           auth ??
           (Platform.isAndroid && config.androidServerClientId.isNotEmpty
               ? PlayServicesAuth(config)
               : GoogleAuth(config)),
       tokens = tokens ?? SecureTokenStore(),
       _folder = folder ?? ((token) => DriveAppFolder(token)),
       _openBrowser =
           openBrowser ??
           ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

  final EventStore store;
  final AppSettings settings;
  final OAuthConfig config;
  final GoogleAuth auth;
  final TokenStore tokens;
  final SyncFolder Function(Future<String> Function() token) _folder;
  final Future<bool> Function(Uri url) _openBrowser;
  final List<Duration> retryDelays;

  /// Where versions before 0.9.2 kept the token (moved to [tokens] on start).
  static const _legacyTokenKey = 'syncRefreshToken';
  static const _lastKey = 'syncLast';
  static const _fileKey = 'syncSnapshotFileId';
  static const _writerKey = 'syncWriterId';

  String get _writer {
    final saved = settings.readValue(_writerKey);
    if (saved != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(saved))
      return saved;
    final id = newId();
    settings.writeValue(_writerKey, id);
    return id;
  }

  /// Don't sync again on every app switch.
  static const minGap = Duration(minutes: 2);

  bool _signingIn = false;
  bool _disconnecting = false;
  bool _syncing = false;
  String? _error;
  bool _offline = false;
  int _retry = 0;
  Timer? _retryTimer;
  int _syncedCount = -1;
  DateTime? _syncedSettings;
  int _generation = 0;
  bool _started = false;
  Future<void>? _tokenWrites;

  bool _current(int generation) => !_disposed && generation == _generation;
  bool get _dirty =>
      store.events.length != _syncedCount ||
      settings.changedAt != _syncedSettings;
  Future<bool>? _running;
  String? _refreshToken;
  Future<void>? _loaded;
  bool _isLoaded = false;

  bool get connected => _refreshToken != null;
  bool get configured =>
      config.isSet ||
      (auth is PlayServicesAuth && config.androidServerClientId.isNotEmpty);
  DateTime? get lastSync =>
      DateTime.tryParse(settings.readValue(_lastKey) ?? '');
  String? get error => _error;

  SyncStatus get status {
    if (!configured) return SyncStatus.notSetUp;
    if (_disconnecting) return SyncStatus.disconnecting;
    if (_signingIn) return SyncStatus.signingIn;
    if (_syncing) return SyncStatus.syncing;
    if (_offline) return SyncStatus.offline;
    if (_error != null) return SyncStatus.error;
    if (!connected) return SyncStatus.signedOut;
    return SyncStatus.idle;
  }

  /// Hooks into the app lifecycle and syncs once for the app opening.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final last = lastSync;
        if (last == null || DateTime.now().difference(last) > minGap)
          unawaited(sync());
      case AppLifecycleState.paused ||
          AppLifecycleState.hidden ||
          AppLifecycleState.detached:
        // Closing or leaving the app: upload what changed since the last sync.
        if (_dirty) unawaited(sync());
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Reads the saved sign-in once (and moves it out of the preferences of older versions).
  Future<void> _load() async {
    if (_isLoaded) return;
    await (_loaded ??= _readSaved());
  }

  Future<void> _readSaved() async {
    try {
      _refreshToken = await tokens.read();
    } catch (e) {
      debugPrint('Sync sign-in unreadable: $e');
    }
    final legacy = settings.readValue(_legacyTokenKey);
    if (legacy != null) {
      _refreshToken ??= legacy;
      if (await _save(_refreshToken))
        settings.writeValue(_legacyTokenKey, null);
    }
    _isLoaded = true;
    notifyListeners();
  }

  /// Stores the token; returns false when it could only be kept in memory.
  Future<bool> _save(String? token) {
    // Serialize credential writes: a delayed connect must never overwrite a
    // later disconnect (or the credentials of a newly selected account).
    Future<bool> persist() async {
      try {
        await tokens.write(token);
        return true;
      } catch (e) {
        debugPrint('Sync sign-in not saved: $e');
        return false;
      }
    }

    final result = _tokenWrites == null
        ? persist()
        : _tokenWrites!.then((_) => persist());
    _tokenWrites = result.then((_) {});
    return result;
  }

  Future<void> connect() async {
    if (!configured || _signingIn || _disconnecting || _disposed) return;
    final generation = ++_generation;
    _running = null;
    _syncing = false;
    _signingIn = true;
    _offline = false;
    _error = null;
    _retryTimer?.cancel();
    notifyListeners();
    try {
      await _load();
      if (!_current(generation)) return;
      final refresh = await auth.signIn(_openBrowser);
      if (!_current(generation)) return;
      _refreshToken = refresh;
      // A cached file id belongs to the previous account, never the new one.
      settings
        ..writeValue(_fileKey, null)
        ..writeValue(_lastKey, null);
      _syncedCount = -1;
      _syncedSettings = null;
      await _save(refresh);
    } on AuthException catch (e) {
      if (_current(generation)) _error = e.message;
    } catch (e) {
      if (_current(generation)) _error = 'Sign-in failed: $e';
    } finally {
      if (_current(generation)) {
        _signingIn = false;
        notifyListeners();
      }
    }
    if (_current(generation) && connected) await sync();
  }

  Future<void> cancelSignIn() async {
    if (!_signingIn) return;
    ++_generation;
    _signingIn = false;
    _error = null;
    notifyListeners();
    await auth.cancelSignIn();
  }

  /// Forgets the Google account on this device. Data already in Drive stays there.
  Future<void> disconnect() async {
    if (_disposed || _disconnecting) return;
    final generation = ++_generation;
    _running = null;
    _syncing = false;
    _signingIn = false;
    _disconnecting = true;
    _retryTimer?.cancel();
    notifyListeners();
    try {
      await auth.cancelSignIn();
      await _load();
      if (!_current(generation)) return;
      final token = _refreshToken;
      _refreshToken = null;
      _error = null;
      _offline = false;
      _syncedCount = -1;
      _syncedSettings = null;
      settings
        ..writeValue(_legacyTokenKey, null)
        ..writeValue(_lastKey, null)
        ..writeValue(_fileKey, null);
      await _save(null);
      if (!_current(generation)) return;
      // Finish revoking before allowing another sign-in: a late Play-services
      // disconnect must not clear the next account's authorization.
      if (token != null) await auth.revoke(token);
    } finally {
      if (_current(generation)) {
        _disconnecting = false;
        notifyListeners();
      }
    }
  }

  /// Merges with the copy in Drive. Returns true on success.
  Future<bool> sync() {
    if (_disposed || _signingIn || _disconnecting) return Future.value(false);
    if (_running != null) return _running!;
    late final Future<bool> running;
    running = _sync(_generation).whenComplete(() {
      if (identical(_running, running)) _running = null;
    });
    return _running = running;
  }

  Future<bool> _sync(
    int generation, {
    bool afterCreate = false,
    bool refreshedAuthorization = false,
  }) async {
    if (!configured || !_current(generation)) return false;
    await _load();
    if (!_current(generation)) return false;
    final refresh = _refreshToken;
    if (refresh == null) return false;
    _retryTimer?.cancel();
    _syncing = true;
    notifyListeners();
    try {
      final folder = _folder(() async {
        if (!_current(generation)) throw const _SyncCancelled();
        final token = await auth.accessToken(refresh);
        if (!_current(generation)) throw const _SyncCancelled();
        return token;
      });
      final writer = _writer;
      final files = <String, RemoteFile>{};
      final snapshots = <String>{};
      for (final name in [SyncPayload.fileName, SyncPayload.snapshotFileName]) {
        final found = await folder.findAll(name);
        if (!_current(generation)) return false;
        for (final file in found) {
          files[file.id] = file;
          if (name == SyncPayload.snapshotFileName) snapshots.add(file.id);
        }
      }
      // A recently created file may not yet appear in a listing. Its locally
      // retained id still lets its owner read it without creating another copy.
      final cached = settings.readValue(_fileKey);
      if (cached != null && !files.containsKey(cached)) {
        files[cached] = RemoteFile(cached, null);
        snapshots.add(cached);
      }
      String? fileId;
      SyncPayload? own;
      for (final file in files.values) {
        List<int> bytes;
        try {
          bytes = await folder.read(file.id);
        } on DriveException catch (e) {
          if (!_current(generation)) return false;
          if (e.status == HttpStatus.notFound) continue;
          rethrow;
        }
        if (!_current(generation)) return false;
        if (bytes.isEmpty) continue;
        final payload = SyncPayload.decode(bytes);
        await store.merge(payload.events);
        if (!_current(generation)) return false;
        final remoteSettings = payload.settings;
        if (remoteSettings != null && payload.settingsChanged != null) {
          settings.applySync(remoteSettings, payload.settingsChanged!);
        }
        // Only this installation's snapshot can be updated. Other devices'
        // snapshots and every legacy shared file are always read-only.
        if (snapshots.contains(file.id) &&
            payload.writer == writer &&
            (fileId == null || file.id.compareTo(fileId) < 0)) {
          fileId = file.id;
          own = payload;
        }
      }
      final ownIds = {for (final e in own?.events ?? const <AppEvent>[]) e.id};
      final settingsNewer =
          settings.changedAt != null &&
          (own?.settingsChanged == null ||
              settings.changedAt!.isAfter(own!.settingsChanged!));
      final upload =
          own == null ||
          store.events.any((e) => !ownIds.contains(e.id)) ||
          settingsNewer;
      var created = false;
      final syncedCount = store.events.length;
      final syncedSettings = settings.changedAt;
      if (upload) {
        final bytes = SyncPayload(
          events: store.events,
          settings: settings.toSyncJson(),
          settingsChanged: settings.changedAt,
          writer: writer,
        ).encode();
        if (fileId == null) {
          fileId = await folder.create(SyncPayload.snapshotFileName, bytes);
          created = true;
        } else {
          await folder.write(fileId, bytes);
        }
      }
      if (!_current(generation)) return false;
      settings
        ..writeValue(_fileKey, fileId)
        ..writeValue(_lastKey, DateTime.now().toUtc().toIso8601String());
      _syncedCount = syncedCount;
      _syncedSettings = syncedSettings;
      _error = null;
      _offline = false;
      _retry = 0;
      // Changes made during the upload were not in its payload. Send them in
      // another pass instead of marking them synced or waiting for an app switch.
      if (_dirty || (created && !afterCreate))
        return await _sync(
          generation,
          afterCreate: true,
          refreshedAuthorization: refreshedAuthorization,
        );
      return true;
    } on AuthException catch (e) {
      if (!_current(generation)) return false;
      _offline = false;
      _error = e.signInAgain
          ? 'Google sign-in expired. Connect again.'
          : e.message;
      if (e.signInAgain) {
        _refreshToken = null;
        await _save(null);
      }
      return false;
    } on SocketException {
      if (!_current(generation)) return false;
      _goOffline();
      return false;
    } on HttpException {
      if (!_current(generation)) return false;
      _goOffline();
      return false;
    } on TimeoutException {
      if (!_current(generation)) return false;
      _goOffline();
      return false;
    } catch (e) {
      if (!_current(generation)) return false;
      // A definite Drive response replaces any previous network failure.
      // Otherwise an expired grant can be hidden behind the Offline status.
      if (e is DriveException) _offline = false;
      if (e is DriveException && e.status == HttpStatus.unauthorized) {
        if (!refreshedAuthorization) {
          try {
            await auth.invalidateAccessToken(refresh);
          } catch (_) {
            if (_current(generation)) {
              _error = 'Could not refresh Google sign-in. Try syncing again.';
            }
            return false;
          }
          if (!_current(generation)) return false;
          return await _sync(
            generation,
            afterCreate: afterCreate,
            refreshedAuthorization: true,
          );
        }
        // A fresh token was also rejected. Retrying the cached credential
        // forever cannot recover a removed grant; offer Connect instead.
        _refreshToken = null;
        _error = 'Google sign-in expired. Connect again.';
        await _save(null);
        return false;
      }
      _error = e is DriveException && e.status >= 500
          ? 'Google Drive is busy. Will try again later.'
          : 'Sync failed: $e';
      if (e is DriveException && e.status >= 500) _scheduleRetry();
      return false;
    } finally {
      if (_current(generation)) {
        _syncing = false;
        notifyListeners();
      }
    }
  }

  /// No network: try again a few times with growing pauses, then wait for the next app open.
  void _goOffline() {
    _offline = true;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || !connected || _retry >= retryDelays.length) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelays[_retry++], () => unawaited(sync()));
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _SyncCancelled implements Exception {
  const _SyncCancelled();
}

/// Gives widgets the app's [SyncService].
class SyncScope extends InheritedNotifier<SyncService> {
  const SyncScope({super.key, required SyncService sync, required super.child})
    : super(notifier: sync);

  static SyncService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()!.notifier!;
}
