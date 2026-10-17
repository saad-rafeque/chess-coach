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

enum SyncStatus { notSetUp, signedOut, signingIn, idle, syncing, offline, error }

/// Keeps devices in step through one file in the user's Google Drive app folder.
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
    this.retryDelays = const [Duration(minutes: 1), Duration(minutes: 3), Duration(minutes: 10), Duration(minutes: 30)],
  })  : auth = auth ??
            (Platform.isAndroid && config.androidServerClientId.isNotEmpty ? PlayServicesAuth(config) : GoogleAuth(config)),
        tokens = tokens ?? FileTokenStore(),
        _folder = folder ?? ((token) => DriveAppFolder(token)),
        _openBrowser = openBrowser ?? ((url) => launchUrl(url, mode: LaunchMode.externalApplication));

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
  static const _fileKey = 'syncFileId';

  /// Don't sync again on every app switch.
  static const minGap = Duration(minutes: 2);

  bool _signingIn = false;
  bool _syncing = false;
  String? _error;
  bool _offline = false;
  int _retry = 0;
  Timer? _retryTimer;
  int _syncedCount = -1;
  Future<bool>? _running;
  String? _refreshToken;
  Future<void>? _loaded;
  bool _isLoaded = false;

  bool get connected => _refreshToken != null;
  DateTime? get lastSync => DateTime.tryParse(settings.readValue(_lastKey) ?? '');
  String? get error => _error;

  SyncStatus get status {
    if (!config.isSet) return SyncStatus.notSetUp;
    if (_signingIn) return SyncStatus.signingIn;
    if (!connected) return SyncStatus.signedOut;
    if (_syncing) return SyncStatus.syncing;
    if (_offline) return SyncStatus.offline;
    if (_error != null) return SyncStatus.error;
    return SyncStatus.idle;
  }

  /// Hooks into the app lifecycle and syncs once for the app opening.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    unawaited(sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final last = lastSync;
        if (last == null || DateTime.now().difference(last) > minGap) unawaited(sync());
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        // Closing or leaving the app: upload what changed since the last sync.
        if (store.events.length != _syncedCount) unawaited(sync());
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
      if (await _save(_refreshToken)) settings.writeValue(_legacyTokenKey, null);
    }
    _isLoaded = true;
    notifyListeners();
  }

  /// Stores the token; returns false when it could only be kept in memory.
  Future<bool> _save(String? token) async {
    try {
      await tokens.write(token);
      return true;
    } catch (e) {
      debugPrint('Sync sign-in not saved: $e');
      return false;
    }
  }

  Future<void> connect() async {
    if (!config.isSet || _signingIn) return;
    _signingIn = true;
    _error = null;
    notifyListeners();
    try {
      await _load();
      final refresh = await auth.signIn(_openBrowser);
      _refreshToken = refresh;
      await _save(refresh);
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Sign-in failed: $e';
    } finally {
      _signingIn = false;
      notifyListeners();
    }
    if (connected) await sync();
  }

  Future<void> cancelSignIn() => auth.cancelSignIn();

  /// Forgets the Google account on this device. Data already in Drive stays there.
  Future<void> disconnect() async {
    await _load();
    final token = _refreshToken;
    _refreshToken = null;
    _retryTimer?.cancel();
    await _save(null);
    settings
      ..writeValue(_legacyTokenKey, null)
      ..writeValue(_lastKey, null)
      ..writeValue(_fileKey, null);
    _error = null;
    _offline = false;
    notifyListeners();
    if (token != null) await auth.revoke(token);
  }

  /// Merges with the copy in Drive. Returns true on success.
  Future<bool> sync() => _running ??= _sync().whenComplete(() => _running = null);

  Future<bool> _sync() async {
    if (!config.isSet) return false;
    await _load();
    final refresh = _refreshToken;
    if (refresh == null) return false;
    _retryTimer?.cancel();
    _syncing = true;
    notifyListeners();
    try {
      final folder = _folder(() => auth.accessToken(refresh));
      var fileId = settings.readValue(_fileKey);
      RemoteFile? remote;
      if (fileId == null) {
        remote = await folder.find(SyncPayload.fileName);
        fileId = remote?.id;
      }
      var upload = fileId == null;
      if (fileId != null) {
        List<int> bytes;
        try {
          bytes = await folder.read(fileId);
        } on DriveException catch (e) {
          if (e.status != HttpStatus.notFound) rethrow;
          // The file was deleted (or belongs to an old sign-in): start a new one.
          settings.writeValue(_fileKey, null);
          remote = await folder.find(SyncPayload.fileName);
          fileId = remote?.id;
          bytes = fileId == null ? const [] : await folder.read(fileId);
        }
        if (bytes.isEmpty) {
          upload = true;
        } else {
          final payload = SyncPayload.decode(bytes);
          final remoteIds = {for (final e in payload.events) e.id};
          await store.merge(payload.events);
          final s = payload.settings;
          if (s != null && payload.settingsChanged != null) settings.applySync(s, payload.settingsChanged!);
          final settingsNewer = settings.changedAt != null &&
              (payload.settingsChanged == null || settings.changedAt!.isAfter(payload.settingsChanged!));
          upload = store.events.any((e) => !remoteIds.contains(e.id)) || settingsNewer;
        }
      }
      if (upload) {
        final bytes = SyncPayload(
          events: store.events,
          settings: settings.toSyncJson(),
          settingsChanged: settings.changedAt,
        ).encode();
        if (fileId == null) {
          fileId = await folder.create(SyncPayload.fileName, bytes);
        } else {
          await folder.write(fileId, bytes);
        }
      }
      settings
        ..writeValue(_fileKey, fileId)
        ..writeValue(_lastKey, DateTime.now().toUtc().toIso8601String());
      _syncedCount = store.events.length;
      _error = null;
      _offline = false;
      _retry = 0;
      return true;
    } on AuthException catch (e) {
      _error = e.signInAgain ? 'Google sign-in expired. Connect again.' : e.message;
      if (e.signInAgain) {
        _refreshToken = null;
        await _save(null);
      }
      return false;
    } on SocketException {
      _goOffline();
      return false;
    } on HttpException {
      _goOffline();
      return false;
    } on TimeoutException {
      _goOffline();
      return false;
    } catch (e) {
      _error = e is DriveException && e.status >= 500
          ? 'Google Drive is busy. Will try again later.'
          : 'Sync failed: $e';
      if (e is DriveException && e.status >= 500) _scheduleRetry();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// No network: try again a few times with growing pauses, then wait for the next app open.
  void _goOffline() {
    _offline = true;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_retry >= retryDelays.length) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelays[_retry++], () => unawaited(sync()));
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Gives widgets the app's [SyncService].
class SyncScope extends InheritedNotifier<SyncService> {
  const SyncScope({super.key, required SyncService sync, required super.child}) : super(notifier: sync);

  static SyncService of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SyncScope>()!.notifier!;
}
