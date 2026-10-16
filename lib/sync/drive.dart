import 'dart:convert';
import 'dart:io';

import '../data/event_store.dart';

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
  String toString() => 'Google Drive error $status: $message';
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
    final client = _client();
    try {
      final uri = Uri.parse('$base$path').replace(queryParameters: query);
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${await token()}');
      if (body != null) {
        req.headers.set(HttpHeaders.contentTypeHeader, contentType ?? 'application/octet-stream');
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
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
    return RemoteFile(f['id'] as String, DateTime.tryParse(f['modifiedTime'] as String? ?? ''));
  }

  @override
  Future<List<int>> read(String id) async => (await _send('GET', '/drive/v3/files/$id', query: {'alt': 'media'})).$2;

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
    return (jsonDecode(utf8.decode(res)) as Map<String, dynamic>)['id'] as String;
  }

  @override
  Future<void> write(String id, List<int> bytes) async {
    await _send('PATCH', '/upload/drive/v3/files/$id', query: {'uploadType': 'media'}, body: bytes);
  }
}

/// Everything that is synced, as one gzip-compressed JSON file.
class SyncPayload {
  const SyncPayload({required this.events, this.settings, this.settingsChanged});

  factory SyncPayload.decode(List<int> bytes) {
    final j = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
    final version = j['version'] as int? ?? 1;
    if (version > formatVersion) throw FormatException('Sync file is from a newer app version ($version).');
    return SyncPayload(
      events: [
        for (final e in (j['events'] as List<dynamic>? ?? const [])) AppEvent.fromJson((e as Map).cast<String, dynamic>()),
      ],
      settings: (j['settings'] as Map?)?.cast<String, dynamic>(),
      settingsChanged: DateTime.tryParse(j['settingsChanged'] as String? ?? ''),
    );
  }

  static const formatVersion = 1;
  static const fileName = 'chess-coach-sync.json.gz';

  final List<AppEvent> events;
  final Map<String, dynamic>? settings;
  final DateTime? settingsChanged;

  List<int> encode() => gzip.encode(utf8.encode(jsonEncode({
        'version': formatVersion,
        'events': [for (final e in events) e.toJson()],
        'settings': ?settings,
        if (settingsChanged != null) 'settingsChanged': settingsChanged!.toUtc().toIso8601String(),
      })));
}
