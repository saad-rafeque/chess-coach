import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../app/settings.dart';
import '../../data/data_folder.dart';

/// A small instruction-tuned language model in GGUF format (run by llama.cpp).
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.detail,
    required this.fileName,
    required this.url,
    required this.bytes,
    required this.sha256,
  });

  final String id;
  final String name;
  final String detail;
  final String fileName;
  final String url;
  final int bytes;
  final String sha256;

  String get sizeLabel => bytes >= 1e9 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${(bytes / 1e6).round()} MB';
}

/// Qwen2.5 Instruct models (Apache-2.0), the official GGUF builds on Hugging Face.
const explainerModels = [
  ModelSpec(
    id: 'qwen2.5-0.5b',
    name: 'Small',
    detail: 'Qwen2.5 0.5B. Fast on phones.',
    fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    url: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
    bytes: 491400032,
    sha256: '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db',
  ),
  ModelSpec(
    id: 'qwen2.5-1.5b',
    name: 'Better',
    detail: 'Qwen2.5 1.5B. Nicer English; best on a computer.',
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
    bytes: 1117320736,
    sha256: '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
  ),
];

ModelSpec modelById(String? id) =>
    explainerModels.firstWhere((m) => m.id == id, orElse: () => explainerModels.first);

enum ModelStatus { absent, downloading, verifying, ready, failed }

/// Downloads, verifies and deletes explainer models. Nothing is downloaded unless the
/// player asks for it in Settings; downloads resume after an interruption.
///
/// llama.cpp only ever opens a file whose sha256 matched: after a download, and again whenever
/// the file's size or date differs from the last check (it lives in Documents on desktops,
/// where other programs could replace it). The last check is remembered in [marks].
class ModelStore extends ChangeNotifier {
  ModelStore({
    Future<Directory> Function()? directory,
    HttpClient Function()? client,
    AppSettings? marks,
    bool verifyAtLoad = true,
  })  : _directory = directory ?? _defaultDirectory,
        _client = client ?? HttpClient.new,
        _marks = marks ?? AppSettings.memory(),
        _verifyAtLoad = verifyAtLoad;

  /// Whether [verifyForLoad] hashes before llama.cpp opens a file. Tests that
  /// stand a sparse file in for the model turn this off.
  final bool _verifyAtLoad;

  static Future<Directory> _defaultDirectory() async {
    final base = await dataFolder();
    return Directory('${base.path}${Platform.pathSeparator}models');
  }

  final Future<Directory> Function() _directory;
  final HttpClient Function() _client;
  final AppSettings _marks;

  final _status = <String, ModelStatus>{};
  final _received = <String, int>{};
  final _errors = <String, String>{};
  final _sessionVerified = <String>{};
  HttpClient? _active;
  bool _cancelled = false;

  ModelStatus status(ModelSpec m) => _status[m.id] ?? ModelStatus.absent;
  double progress(ModelSpec m) => (_received[m.id] ?? 0) / m.bytes;
  String? error(ModelSpec m) => _errors[m.id];
  bool get busy => _status.values.any((s) => s == ModelStatus.downloading || s == ModelStatus.verifying);

  Future<File> fileFor(ModelSpec m) async => File('${(await _directory()).path}${Platform.pathSeparator}${m.fileName}');

  static String _markKey(ModelSpec m) => 'modelVerified.${m.id}';
  static String _stamp(File f) {
    final s = f.statSync();
    return '${s.size}:${s.modified.microsecondsSinceEpoch}';
  }

  /// Records that [m]'s file on disk is the checked one.
  Future<void> markVerified(ModelSpec m) async => _marks.writeValue(_markKey(m), _stamp(await fileFor(m)));

  /// Re-checks [m]'s file against its pinned sha256, once per app session,
  /// right before llama.cpp opens it. The stamp check in [refresh] is fast but
  /// can be faked by restoring a file's old size and date, so a load never
  /// relies on the stamp alone.
  Future<void> verifyForLoad(ModelSpec m) async {
    if (!_verifyAtLoad || _sessionVerified.contains(m.id)) return;
    final f = await fileFor(m);
    if (!f.existsSync()) {
      _status[m.id] = ModelStatus.absent;
      notifyListeners();
      throw const FormatException('The model file is missing. Download it again.');
    }
    final hash = await Isolate.run(() => _sha256(f.path));
    if (hash != m.sha256) {
      _marks.writeValue(_markKey(m), null);
      _status[m.id] = ModelStatus.failed;
      _errors[m.id] = 'The model file was changed or damaged. Download it again.';
      notifyListeners();
      throw const FormatException('The model file was changed or damaged. Download it again.');
    }
    _sessionVerified.add(m.id);
  }

  /// Checks which models are already on disk, verifying any file that changed since its last check.
  Future<void> refresh() async {
    for (final m in explainerModels) {
      if (_status[m.id] == ModelStatus.downloading || _status[m.id] == ModelStatus.verifying) continue;
      final f = await fileFor(m);
      if (!f.existsSync() || f.lengthSync() != m.bytes) {
        _status[m.id] = ModelStatus.absent;
        continue;
      }
      if (_marks.readValue(_markKey(m)) == _stamp(f)) {
        _status[m.id] = ModelStatus.ready;
        continue;
      }
      _status[m.id] = ModelStatus.verifying;
      notifyListeners();
      final path = f.path;
      final hash = await Isolate.run(() => _sha256(path));
      if (hash == m.sha256) {
        await markVerified(m);
        _status[m.id] = ModelStatus.ready;
      } else {
        _marks.writeValue(_markKey(m), null);
        _status[m.id] = ModelStatus.failed;
        _errors[m.id] = 'The model file was changed or damaged. Download it again.';
      }
    }
    notifyListeners();
  }

  Future<void> download(ModelSpec m) async {
    if (busy) return;
    _cancelled = false;
    _errors.remove(m.id);
    _status[m.id] = ModelStatus.downloading;
    notifyListeners();
    final target = await fileFor(m);
    final part = File('${target.path}.part');
    try {
      await target.parent.create(recursive: true);
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > m.bytes) {
        part.deleteSync();
        have = 0;
      }
      _received[m.id] = have;
      final client = _active = _client()..connectionTimeout = const Duration(seconds: 30);
      final response = await _openDownload(client, Uri.parse(m.url), resumeAt: have);
      if (response.statusCode == HttpStatus.ok) {
        have = 0; // The server ignored the range: start over.
      } else if (response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Server answered ${response.statusCode}');
      }
      _received[m.id] = have;
      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      var lastNotify = DateTime.now();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 60))) {
          if (_cancelled) throw const _Cancelled();
          if (_received[m.id]! + chunk.length > m.bytes) throw const HttpException('The download was too large.');
          sink.add(chunk);
          _received[m.id] = _received[m.id]! + chunk.length;
          if (DateTime.now().difference(lastNotify) > const Duration(milliseconds: 250)) {
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (part.lengthSync() != m.bytes) throw const HttpException('The download was incomplete. Try again.');
      _status[m.id] = ModelStatus.verifying;
      notifyListeners();
      final hash = await Isolate.run(() => _sha256(part.path));
      if (hash != m.sha256) {
        part.deleteSync();
        throw const FormatException('The downloaded file was damaged. Try again.');
      }
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
      await markVerified(m);
      _sessionVerified.add(m.id); // just hashed it, no need to do it again this session
      _status[m.id] = ModelStatus.ready;
    } on _Cancelled {
      _status[m.id] = ModelStatus.absent;
    } on TimeoutException {
      _status[m.id] = ModelStatus.failed;
      _errors[m.id] = 'The download stalled. Check the connection and try again.';
    } catch (e) {
      _status[m.id] = ModelStatus.failed;
      _errors[m.id] = e is HttpException || e is FormatException ? _message(e) : 'Download failed: $e';
    } finally {
      _active?.close(force: true);
      _active = null;
      notifyListeners();
    }
  }

  /// Opens a model download, following redirects only to huggingface.co hosts
  /// over HTTPS. Every hop is checked before the next request goes out, so no
  /// request ever reaches a host that was not validated. The file is checked
  /// by its hash anyway; this just keeps the download itself on Hugging Face.
  Future<HttpClientResponse> _openDownload(HttpClient client, Uri url, {int resumeAt = 0}) async {
    var target = url;
    for (var hops = 0; ; hops++) {
      final request = await client.getUrl(target);
      request.followRedirects = false;
      if (resumeAt > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeAt-');
      final res = await request.close().timeout(const Duration(seconds: 60));
      if (res.isRedirect) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null || hops >= 4) throw const HttpException('The download link redirected too much.');
        final next = target.resolve(location);
        final allowed = next.host == 'huggingface.co' || next.host.endsWith('.huggingface.co');
        if ((next.hasScheme && next.scheme != 'https') || !allowed) {
          throw const HttpException('The download link is not secure.');
        }
        target = next;
        continue;
      }
      return res;
    }
  }

  /// Stops a running download; the part already received is kept for later.
  void cancel() {
    _cancelled = true;
    _active?.close(force: true);
  }

  Future<void> delete(ModelSpec m) async {
    final f = await fileFor(m);
    for (final file in [f, File('${f.path}.part')]) {
      if (file.existsSync()) file.deleteSync();
    }
    _status[m.id] = ModelStatus.absent;
    _errors.remove(m.id);
    _marks.writeValue(_markKey(m), null);
    _received.remove(m.id);
    _sessionVerified.remove(m.id);
    notifyListeners();
  }
}

String _message(Object e) => switch (e) {
      HttpException(:final message) => message,
      FormatException(:final message) => message,
      _ => '$e',
    };

class _Cancelled implements Exception {
  const _Cancelled();
}

Future<String> _sha256(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
