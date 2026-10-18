import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'release_key.dart';
import 'version.dart';

/// A newer release on GitHub, with the file for this device and its checksum.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes, required this.pageUrl, this.asset, this.sha256});

  final String version;
  final String notes;
  final String pageUrl;

  /// The download for this platform and install kind (null: open [pageUrl] instead).
  final ({String name, String url, int size})? asset;
  final String? sha256;
}

/// How this copy was installed, which decides how it updates itself.
enum InstallKind { android, windowsSetup, appImage, deb, other }

enum UpdateStatus { idle, checking, downloading, installing, failed }

/// Compares dotted versions: positive when [a] is newer than [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      [for (final p in v.replaceFirst(RegExp('^v'), '').split('+').first.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Finds new releases on GitHub and installs them, after checking each file against the release's
/// SHA256SUMS.txt — which itself must carry a valid signature by the release key pinned in
/// [releaseSigningPublicKeyHex]. Android also refuses an APK signed with another key, so a tampered
/// download can't replace the app.
class Updater extends ChangeNotifier {
  Updater({
    this.repo = 'saad-rafeque/chess-coach',
    this.current = appVersion,
    InstallKind? kind,
    HttpClient Function()? client,
    this.api = 'https://api.github.com',
    this.web = 'https://github.com',
    Map<String, String>? environment,
    Future<Directory> Function()? tempDir,
    this.releaseKeyHex = releaseSigningPublicKeyHex,
  })  : _tempDir = tempDir ?? getTemporaryDirectory,
        kind = kind ?? detectInstallKind(environment ?? Platform.environment),
        _client = client ?? HttpClient.new,
        _env = environment ?? Platform.environment;

  final String repo;
  final String current;
  final InstallKind kind;
  final String api;
  final String web;
  final HttpClient Function() _client;
  final Map<String, String> _env;
  final Future<Directory> Function() _tempDir;

  /// The public half of the release signing key (hex), replaceable in tests.
  final String releaseKeyHex;

  ReleaseInfo? available;
  UpdateStatus status = UpdateStatus.idle;
  double progress = 0;
  String? error;
  DateTime? _checked;

  /// "Later" hides the offer until the app starts again.
  bool dismissed = false;

  static InstallKind detectInstallKind(Map<String, String> env) {
    if (kIsWeb) return InstallKind.other;
    if (Platform.isAndroid) return InstallKind.android;
    if (Platform.isWindows) return InstallKind.windowsSetup;
    if (Platform.isLinux) {
      if ((env['APPIMAGE'] ?? '').isNotEmpty) return InstallKind.appImage;
      if (Platform.resolvedExecutable.startsWith('/opt/chess-coach/')) return InstallKind.deb;
    }
    return InstallKind.other;
  }

  /// The release file for each install kind.
  static String? assetSuffix(InstallKind kind) => switch (kind) {
        InstallKind.android => '-android-arm64.apk',
        InstallKind.windowsSetup => '-Setup.exe',
        InstallKind.appImage => '-x86_64.AppImage',
        InstallKind.deb => '-amd64.deb',
        InstallKind.other => null,
      };

  /// Looks for a newer release (at most every few hours, unless [force]).
  Future<void> check({bool force = false}) async {
    if (status == UpdateStatus.checking || status == UpdateStatus.downloading) return;
    final last = _checked;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(hours: 4)) return;
    status = UpdateStatus.checking;
    error = null;
    notifyListeners();
    try {
      final json = jsonDecode(utf8.decode(await _get(Uri.parse('$api/repos/$repo/releases/latest'), 1 << 20)));
      if (json is! Map) throw const FormatException('Unexpected answer from GitHub.');
      final tag = json['tag_name'];
      if (tag is! String || !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) throw const FormatException('Bad release tag.');
      _checked = DateTime.now();
      if (compareVersions(tag, current) <= 0) {
        available = null;
        return;
      }
      final assets = <String, ({String name, String url, int size})>{};
      for (final a in (json['assets'] as List? ?? const [])) {
        if (a is! Map || a['name'] is! String || a['browser_download_url'] is! String) continue;
        final url = a['browser_download_url'] as String;
        // Only files attached to this repository's releases.
        if (!url.startsWith('$web/$repo/releases/download/$tag/')) continue;
        assets[a['name'] as String] = (name: a['name'] as String, url: url, size: (a['size'] as num?)?.toInt() ?? 0);
      }
      final suffix = assetSuffix(kind);
      final asset = suffix == null ? null : assets.values.where((a) => a.name.endsWith(suffix)).firstOrNull;
      String? sum;
      final sums = assets['SHA256SUMS.txt'];
      if (asset != null && sums != null) {
        final sumsBytes = await _get(Uri.parse(sums.url), 64 * 1024);
        // Only checksums signed by the pinned release key are trusted (see
        // release_key.dart); anything else gets the release page instead.
        final sig = assets['SHA256SUMS.txt.sig'];
        if (sig != null) {
          try {
            final sigBytes = await _get(Uri.parse(sig.url), 4 * 1024);
            if (verifyReleaseSignature(sumsBytes, sigBytes, releaseKeyHex)) {
              for (final line in const LineSplitter().convert(utf8.decode(sumsBytes))) {
                final m = RegExp(r'^([0-9a-f]{64})\s+\*?(.+)$').firstMatch(line.trim());
                if (m != null && m[2] == asset.name) sum = m[1];
              }
            }
          } catch (_) {
            // Missing or unreadable signature: not trusted, the release page is offered.
          }
        }
      }
      available = ReleaseInfo(
        version: tag.substring(1),
        notes: (json['body'] as String? ?? '').trim(),
        pageUrl: '$web/$repo/releases/tag/$tag',
        // Without a checksum the file can't be trusted: send people to the release page instead.
        asset: sum == null ? null : asset,
        sha256: sum,
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
    } finally {
      if (status == UpdateStatus.checking) status = UpdateStatus.idle;
      notifyListeners();
    }
  }

  /// Downloads and installs [available]. Desktop versions restart into the new version.
  Future<void> install() async {
    final release = available;
    if (release == null) return;
    final asset = release.asset;
    if (asset == null || kind == InstallKind.other) {
      await launchUrl(Uri.parse(release.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    status = UpdateStatus.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      if (kind == InstallKind.android) return await _installAndroid(asset, release.sha256!);
      final file = await _download(asset, release.sha256!);
      status = UpdateStatus.installing;
      notifyListeners();
      switch (kind) {
        case InstallKind.windowsSetup:
          // The installer closes this app, replaces it and starts the new version.
          await Process.start(file.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
              mode: ProcessStartMode.detached);
          exit(0);
        case InstallKind.appImage:
          final target = File(_env['APPIMAGE']!);
          final next = File('${target.path}.new');
          await file.copy(next.path);
          await Process.run('chmod', ['755', next.path]);
          await next.rename(target.path);
          await file.delete();
          await Process.start(target.path, const [], mode: ProcessStartMode.detached);
          exit(0);
        case InstallKind.deb:
          // pkexec shows the system's password prompt; the person types it there, never in the app.
          final r = await Process.run('pkexec', ['apt-get', 'install', '-y', file.path]);
          if (r.exitCode != 0) throw ProcessException('pkexec', const [], 'The update was not installed.', r.exitCode);
          await Process.start('/usr/bin/chess-coach', const [], mode: ProcessStartMode.detached);
          exit(0);
        case InstallKind.android || InstallKind.other:
          break;
      }
    } catch (e) {
      status = UpdateStatus.failed;
      error = e is ProcessException ? e.message : 'The update could not be installed: $e';
      notifyListeners();
    }
  }

  Future<void> _installAndroid(({String name, String url, int size}) asset, String sum) async {
    final done = Completer<void>();
    var interrupted = false;
    void fail(String message) {
      if (done.isCompleted) return;
      status = UpdateStatus.failed;
      error = message;
      done.complete();
    }

    OtaUpdate()
        .execute(asset.url, destinationFilename: asset.name, sha256checksum: sum)
        .listen((event) {
      if (interrupted) return; // the timeout below already put up the retry offer
      switch (event.status) {
        case OtaStatus.DOWNLOADING:
          progress = (double.tryParse(event.value ?? '') ?? 0) / 100;
        case OtaStatus.INSTALLING || OtaStatus.INSTALLATION_DONE:
          status = UpdateStatus.installing;
          if (!done.isCompleted) done.complete();
        case OtaStatus.CHECKSUM_ERROR:
          fail('The download was damaged, so it was not installed. Try again.');
        case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
          fail('Allow Chess Coach to install apps (Android asks once), then try again.');
        default:
          fail('The update could not be downloaded (${event.value ?? event.status.name}).');
      }
      notifyListeners();
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      // The install screen was interrupted (for example the player switched
      // away and Android never finished): stop waiting, keep the update on
      // offer, and let one tap start a fresh download instead of a stuck
      // spinner that only a cache clear could end.
      interrupted = true;
      status = UpdateStatus.failed;
      error = 'The installation did not finish. Tap Update now to try again.';
      notifyListeners();
    }
  }

  /// Downloads the update for this device and checks it against the release's checksum.
  @visibleForTesting
  Future<File> downloadVerified() => _download(available!.asset!, available!.sha256!);

  /// Downloads [asset] to a private temporary folder and checks its SHA-256.
  Future<File> _download(({String name, String url, int size}) asset, String sum) async {
    final dir = await _tempDir();
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
    final client = _client()..connectionTimeout = const Duration(seconds: 30);
    try {
      final res = await _open(client, Uri.parse(asset.url));
      final total = asset.size > 0 ? asset.size : res.contentLength;
      final sink = file.openWrite();
      final hashOut = _DigestSink();
      final hash = sha256.startChunkedConversion(hashOut);
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 60))) {
          got += chunk.length;
          if (total > 0 && got > total) throw const HttpException('The download was larger than expected.');
          sink.add(chunk);
          hash.add(chunk);
          if (total > 0) {
            progress = got / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      hash.close();
      if (hashOut.value.toString() != sum) {
        await file.delete();
        throw const FormatException('The download was damaged, so it was not installed. Try again.');
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// GET over HTTPS, following redirects only to GitHub's own hosts. Every hop
  /// is checked before the next request goes out, so no request ever reaches a
  /// host that was not validated.
  Future<HttpClientResponse> _open(HttpClient client, Uri url) async {
    var target = url;
    for (var hops = 0; ; hops++) {
      final req = await client.getUrl(target);
      req.followRedirects = false;
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'ChessCoach/$current')
        ..set(HttpHeaders.acceptHeader, target.host == 'api.github.com' ? 'application/vnd.github+json' : '*/*');
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.isRedirect) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null || hops >= 4) throw const HttpException('The update link redirected too much.');
        final next = target.resolve(location);
        final host = next.host;
        final github = host.isEmpty || host == 'github.com' || host.endsWith('.githubusercontent.com');
        if ((next.hasScheme && next.scheme != 'https') || !github) {
          throw const HttpException('The update link left GitHub.');
        }
        target = next;
        continue;
      }
      if (res.statusCode != HttpStatus.ok) throw HttpException('GitHub answered ${res.statusCode}.');
      return res;
    }
  }

  Future<List<int>> _get(Uri url, int limit) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 20);
    try {
      final res = await _open(client, url);
      final bytes = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 60))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) throw const HttpException('The answer was too large.');
      }
      return bytes;
    } finally {
      client.close();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
