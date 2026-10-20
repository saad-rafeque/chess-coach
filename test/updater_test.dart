import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chess_coach/app/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late HttpServer server;
  late Directory tmp;
  final appImage = utf8.encode('new AppImage bytes');
  var sum = sha256.convert(appImage).toString();
  var tag = 'v9.9.9';
  String base() => 'http://127.0.0.1:${server.port}';

  // The "release key" for these tests: the server signs with the private half,
  // the updater is given the public half.
  final testKey = generateKey();
  var signSums = true;
  var serveSig = true;
  var assetPath = 'ChessCoach-9.9.9-x86_64.AppImage';
  var assetSize = 0;
  var assetRequested = false;
  String sumsBody() => '$sum  ChessCoach-9.9.9-x86_64.AppImage\nabc  other\n';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('upd');
    sum = sha256.convert(appImage).toString();
    tag = 'v9.9.9';
    signSums = true;
    serveSig = true;
    assetPath = 'ChessCoach-9.9.9-x86_64.AppImage';
    assetSize = appImage.length;
    assetRequested = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      final dl = '/saad-rafeque/chess-coach/releases/download/$tag';
      if (path == '/repos/saad-rafeque/chess-coach/releases/latest') {
        req.response.write(jsonEncode({
          'tag_name': tag,
          'body': '## New\n- **Faster** start',
          'assets': [
            {'name': 'ChessCoach-9.9.9-x86_64.AppImage', 'browser_download_url': '${base()}$dl/$assetPath', 'size': assetSize},
            {'name': 'ChessCoach-9.9.9-Setup.exe', 'browser_download_url': 'https://evil.example/ChessCoach-9.9.9-Setup.exe', 'size': 3},
            {'name': 'SHA256SUMS.txt', 'browser_download_url': '${base()}$dl/SHA256SUMS.txt', 'size': 100},
            if (serveSig)
              {'name': 'SHA256SUMS.txt.sig', 'browser_download_url': '${base()}$dl/SHA256SUMS.txt.sig', 'size': 64},
          ],
        }));
      } else if (path == '$dl/SHA256SUMS.txt') {
        req.response.write(sumsBody());
      } else if (path == '$dl/SHA256SUMS.txt.sig') {
        final bytes = utf8.encode(sumsBody());
        if (signSums) {
          req.response.add(sign(testKey.privateKey, Uint8List.fromList(bytes)));
        } else {
          // A signature that does not match the served checksums.
          req.response.add(sign(generateKey().privateKey, Uint8List.fromList(bytes)));
        }
      } else if (path == '$dl/ChessCoach-9.9.9-x86_64.AppImage') {
        assetRequested = true;
        req.response.add(appImage);
      } else if (path == '$dl/hop') {
        await req.response.redirect(Uri.parse('${base()}$dl/ChessCoach-9.9.9-x86_64.AppImage'));
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

  Updater updater(InstallKind kind, {String current = '0.9.2'}) => Updater(
      kind: kind,
      current: current,
      api: base(),
      web: base(),
      environment: const {},
      tempDir: () async => tmp,
      releaseKeyHex: _hex(testKey.publicKey.bytes));

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
    final download = await u.downloadVerified();
    expect(download.readAsBytesSync(), appImage);
    expect(download.parent.path, '${tmp.path}${Platform.pathSeparator}chess-coach-updates');
    if (Platform.isLinux || Platform.isMacOS) {
      expect((await download.parent.stat()).mode & 0x3f, 0);
      expect((await download.stat()).mode & 0x3f, 0);
    }
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
    expect(Directory('${tmp.path}${Platform.pathSeparator}chess-coach-updates').listSync(), isEmpty);
  });

  test('refuses release metadata above the hard download limit', () async {
    assetSize = Updater.maxUpdateBytes + 1;
    final u = updater(InstallKind.appImage);
    await u.check();
    await expectLater(u.downloadVerified(), throwsA(isA<HttpException>()));
    expect(assetRequested, isFalse);
  });

  test('a checksums file with a foreign signature is not trusted', () async {
    signSums = false;
    final u = updater(InstallKind.appImage);
    await u.check();
    expect(u.available!.asset, isNull, reason: 'the signature was not made by the pinned release key');
  });

  test('a checksums file without a signature is not trusted', () async {
    serveSig = false;
    final u = updater(InstallKind.appImage);
    await u.check();
    expect(u.available!.asset, isNull, reason: 'unsigned checksums are not proof of anything');
  });

  test('a download that redirects off GitHub is refused', () async {
    assetPath = 'hop';
    final u = updater(InstallKind.appImage);
    await u.check();
    expect(u.available!.asset, isNotNull);
    await expectLater(u.downloadVerified(), throwsA(isA<HttpException>()));
  });
}
