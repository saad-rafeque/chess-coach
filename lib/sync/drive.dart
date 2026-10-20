import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../data/event_store.dart';
import '../data/event_validation.dart';

/// A file in the remote folder.
class RemoteFile {
  const RemoteFile(this.id, this.modified);

  final String id;
  final DateTime? modified;
}

/// Where the sync file lives. The real one is the Drive appDataFolder; tests use memory.
abstract interface class SyncFolder {
  Future<RemoteFile?> find(String name);
  Future<List<int>> read(String id);
  Future<String> create(String name, List<int> bytes);
  Future<void> write(String id, List<int> bytes);
}

/// Thrown for answers from Drive that aren't network trouble.
class DriveException implements Exception {
  const DriveException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'Google Drive error $status: ${message.length > 200 ? message.substring(0, 200) : message}';
}

/// Drive file ids are short URL-safe strings; anything else never reaches a request path.
final _fileId = RegExp(r'^[A-Za-z0-9_-]{1,200}$');

/// Reads a whole HTTP answer, giving up when it is larger than [limit] bytes or stalls.
Future<List<int>> readLimited(Stream<List<int>> response, int limit) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.timeout(const Duration(seconds: 60))) {
    if (bytes.length + chunk.length > limit) throw const DriveException(413, 'The answer was too large.');
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

/// The app's hidden folder in Google Drive (Drive API v3 over plain HTTPS).
class DriveAppFolder implements SyncFolder {
  DriveAppFolder(this.token, {HttpClient Function()? client, this.base = 'https://www.googleapis.com'})
      : _client = client ?? HttpClient.new;

  /// Returns a valid OAuth access token.
  final Future<String> Function() token;
  final HttpClient Function() _client;
  final String base;

  Future<(int, List<int>)> _send(String method, String path,
      {Map<String, String>? query, List<int>? body, String? contentType}) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse('$base$path').replace(queryParameters: query);
      final req = await client.openUrl(method, uri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${await token()}');
      if (body != null) {
        req.headers.set(HttpHeaders.contentTypeHeader, contentType ?? 'application/octet-stream');
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.isRedirect) {
        throw const DriveException(HttpStatus.movedPermanently, 'Google Drive API unexpectedly redirected.');
      }
      final bytes = await readLimited(res, SyncPayload.maxCompressedBytes);
      if (res.statusCode >= 400) {
        throw DriveException(res.statusCode, utf8.decode(bytes, allowMalformed: true));
      }
      return (res.statusCode, bytes);
    } finally {
      client.close();
    }
  }

  @override
  Future<RemoteFile?> find(String name) async {
    final (_, body) = await _send('GET', '/drive/v3/files', query: {
      'spaces': 'appDataFolder',
      'q': "name = '$name' and trashed = false",
      'fields': 'files(id,modifiedTime)',
      'orderBy': 'modifiedTime desc',
    });
    final files = (jsonDecode(utf8.decode(body)) as Map<String, dynamic>)['files'] as List<dynamic>;
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return RemoteFile(_checkId(f['id']), DateTime.tryParse(f['modifiedTime'] as String? ?? ''));
  }

  static String _checkId(Object? id) {
    if (id is String && _fileId.hasMatch(id)) return id;
    throw const FormatException('Google Drive sent an unexpected file id.');
  }

  /// A stored id that isn't a Drive id counts as a missing file (sync then looks it up again).
  static void _requireId(String id) {
    if (!_fileId.hasMatch(id)) throw const DriveException(HttpStatus.notFound, 'Unknown file id.');
  }

  @override
  Future<List<int>> read(String id) async {
    _requireId(id);
    return (await _send('GET', '/drive/v3/files/$id', query: {'alt': 'media'})).$2;
  }

  @override
  Future<String> create(String name, List<int> bytes) async {
    const boundary = 'chess-coach-sync-boundary';
    final meta = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
    });
    final body = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
          '--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final (_, res) = await _send('POST', '/upload/drive/v3/files',
        query: {'uploadType': 'multipart', 'fields': 'id'},
        body: body,
        contentType: 'multipart/related; boundary=$boundary');
    return _checkId((jsonDecode(utf8.decode(res)) as Map<String, dynamic>)['id']);
  }

  @override
  Future<void> write(String id, List<int> bytes) async {
    _requireId(id);
    await _send('PATCH', '/upload/drive/v3/files/$id', query: {'uploadType': 'media'}, body: bytes);
  }
}

/// Everything that is synced, as one gzip-compressed JSON file.
class SyncPayload {
  const SyncPayload({required this.events, this.settings, this.settingsChanged});

  /// Reads a sync file. Damaged events are skipped one by one (see [parseEvent]); a file that
  /// isn't a sync file at all, or would unpack to more than [maxJsonBytes], is rejected.
  factory SyncPayload.decode(List<int> bytes, {int maxJson = maxJsonBytes}) {
    if (bytes.length > maxCompressedBytes) throw const FormatException('The sync file is too large.');
    final j = jsonDecode(utf8.decode(_gunzip(bytes, maxJson)));
    if (j is! Map) throw const FormatException('The sync file is damaged.');
    final version = j['version'] is int ? j['version'] as int : 1;
    if (version > formatVersion) throw FormatException('Sync file is from a newer app version ($version).');
    final events = j['events'] is List ? j['events'] as List : const [];
    final settings = j['settings'];
    var changed = j['settingsChanged'] is String ? DateTime.tryParse(j['settingsChanged'] as String) : null;
    // A date far in the future would make these settings win forever: ignore it, so this
    // device's settings are uploaded instead.
    if (changed != null && changed.isAfter(DateTime.now().add(const Duration(days: 1)))) changed = null;
    return SyncPayload(
      events: [
        for (final e in events)
          if (parseEvent(e) case final event?) event,
      ],
      settings: settings is Map ? settings.cast<String, dynamic>() : null,
      settingsChanged: changed,
    );
  }

  static const formatVersion = 1;
  static const fileName = 'chess-coach-sync.json.gz';

  /// Size limits for the sync file (years of daily play are a few megabytes).
  static const maxCompressedBytes = 32 << 20;
  static const maxJsonBytes = 128 << 20;

  final List<AppEvent> events;
  final Map<String, dynamic>? settings;
  final DateTime? settingsChanged;

  List<int> encode({int maxCompressed = maxCompressedBytes}) {
    final payload = gzip.encode(utf8.encode(jsonEncode({
          'version': formatVersion,
          'events': [for (final e in events) e.toJson()],
          'settings': settings,
          if (settingsChanged != null) 'settingsChanged': settingsChanged!.toUtc().toIso8601String(),
        })));
    if (payload.length > maxCompressed) {
      throw const FormatException('The sync file is too large.');
    }
    return payload;
  }
}

/// Unpacks gzip data, stopping as soon as the output would pass [limit] bytes (so a tiny
/// crafted file can't fill the memory).
List<int> _gunzip(List<int> bytes, int limit) {
  final out = _LimitedSink(limit);
  final input = gzip.decoder.startChunkedConversion(out);
  for (var i = 0; i < bytes.length; i += 1 << 16) {
    input.add(bytes.sublist(i, math.min(i + (1 << 16), bytes.length)));
  }
  input.close();
  return out.bytes.takeBytes();
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);

  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) throw const FormatException('The sync file is too large.');
    bytes.add(chunk);
  }

  @override
  void close() {}
}
