import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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
class ModelStore extends ChangeNotifier {
  ModelStore({Future<Directory> Function()? directory, HttpClient Function()? client})
      : _directory = directory ?? _defaultDirectory,
        _client = client ?? HttpClient.new;

  static Future<Directory> _defaultDirectory() async {
    final base = await dataFolder();
    return Directory('${base.path}${Platform.pathSeparator}models');
  }

  final Future<Directory> Function() _directory;
  final HttpClient Function() _client;

  final _status = <String, ModelStatus>{};
  final _received = <String, int>{};
  final _errors = <String, String>{};
  HttpClient? _active;
  bool _cancelled = false;

  ModelStatus status(ModelSpec m) => _status[m.id] ?? ModelStatus.absent;
  double progress(ModelSpec m) => (_received[m.id] ?? 0) / m.bytes;
  String? error(ModelSpec m) => _errors[m.id];
  bool get busy => _status.values.any((s) => s == ModelStatus.downloading || s == ModelStatus.verifying);

  Future<File> fileFor(ModelSpec m) async => File('${(await _directory()).path}${Platform.pathSeparator}${m.fileName}');

  /// Checks which models are already on disk.
  Future<void> refresh() async {
    for (final m in explainerModels) {
      if (_status[m.id] == ModelStatus.downloading || _status[m.id] == ModelStatus.verifying) continue;
      final f = await fileFor(m);
      _status[m.id] = f.existsSync() && f.lengthSync() == m.bytes ? ModelStatus.ready : ModelStatus.absent;
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
      final client = _active = _client();
      final request = await client.getUrl(Uri.parse(m.url));
      if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        have = 0; // The server ignored the range: start over.
      } else if (response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Server answered ${response.statusCode}');
      }
      _received[m.id] = have;
      final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      var lastNotify = DateTime.now();
      try {
        await for (final chunk in response) {
          if (_cancelled) throw const _Cancelled();
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
      _status[m.id] = ModelStatus.ready;
    } on _Cancelled {
      _status[m.id] = ModelStatus.absent;
    } catch (e) {
      _status[m.id] = ModelStatus.failed;
      _errors[m.id] = e is HttpException || e is FormatException ? _message(e) : 'Download failed: $e';
    } finally {
      _active?.close(force: true);
      _active = null;
      notifyListeners();
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
    _received.remove(m.id);
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
