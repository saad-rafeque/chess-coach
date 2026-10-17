import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/app/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory tmp;
  final appImage = utf8.encode('new AppImage bytes');
  var sum = sha256.convert(appImage).toString();
  var tag = 'v9.9.9';
  String base() => 'http://127.0.0.1:${server.port}';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('upd');
    sum = sha256.convert(appImage).toString();
    tag = 'v9.9.9';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      final dl = '/saad-rafeque/chess-coach/releases/download/$tag';
      if (path == '/repos/saad-rafeque/chess-coach/releases/latest') {
        req.response.write(jsonEncode({
          'tag_name': tag,
          'body': '## New\n- **Faster** start',
          'assets': [
            {'name': 'ChessCoach-9.9.9-x86_64.AppImage', 'browser_download_url': '${base()}$dl/ChessCoach-9.9.9-x86_64.AppImage', 'size': appImage.length},
            {'name': 'ChessCoach-9.9.9-Setup.exe', 'browser_download_url': 'https://evil.example/ChessCoach-9.9.9-Setup.exe', 'size': 3},
            {'name': 'SHA256SUMS.txt', 'browser_download_url': '${base()}$dl/SHA256SUMS.txt', 'size': 100},
          ],
        }));
      } else if (path == '$dl/SHA256SUMS.txt') {
        req.response.write('$sum  ChessCoach-9.9.9-x86_64.AppImage\nabc  other\n');
      } else if (path == '$dl/ChessCoach-9.9.9-x86_64.AppImage') {
        req.response.add(appImage);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Updater updater(InstallKind kind, {String current = '0.9.2'}) =>
      Updater(kind: kind, current: current, api: base(), web: base(), environment: const {}, tempDir: () async => tmp);

  test('versions compare by number', () {
    expect(compareVersions('v1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('0.9.2', 'v0.9.2'), 0);
    expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
  });

  test('finds a newer release with the file and checksum for this device', () async {
    final u = updater(InstallKind.appImage);
    await u.check();
    final r = u.available!;
    expect(r.version, '9.9.9');
    expect(r.asset!.name, 'ChessCoach-9.9.9-x86_64.AppImage');
    expect(r.sha256, sum);
    expect(r.notes, contains('Faster'));
    expect((await u.downloadVerified()).readAsBytesSync(), appImage);
  });

  test('nothing to offer when up to date', () async {
    final u = updater(InstallKind.appImage, current: '9.9.9');
    await u.check();
    expect(u.available, isNull);
  });

  test('files hosted elsewhere are never offered', () async {
    final u = updater(InstallKind.windowsSetup);
    await u.check();
    expect(u.available!.asset, isNull, reason: 'the Setup link points outside the release');
  });

  test('a damaged download is refused and deleted', () async {
    final u = updater(InstallKind.appImage);
    await u.check();
    sum = '0' * 64;
    final damaged = u.available!;
    u.available = ReleaseInfo(version: damaged.version, notes: '', pageUrl: '', asset: damaged.asset, sha256: sum);
    await expectLater(u.downloadVerified(), throwsFormatException);
    expect(tmp.listSync(), isEmpty);
  });
}
