import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/sync/drive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Drive discovery follows every page and escapes exact file names',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final pages = <String?>[];
      server.listen((request) async {
        final page = request.uri.queryParameters['pageToken'];
        pages.add(page);
        expect(request.uri.queryParameters['spaces'], 'appDataFolder');
        expect(
          request.uri.queryParameters['q'],
          r"name = 'a\'b' and trashed = false",
        );
        request.response.write(
          jsonEncode({
            'files': [
              {'id': page == null ? 'one' : 'two'},
            ],
            if (page == null) 'nextPageToken': 'page-two',
          }),
        );
        await request.response.close();
      });
      final folder = DriveAppFolder(
        () async => 'token',
        base: 'http://127.0.0.1:${server.port}',
      );
      expect((await folder.findAll("a'b")).map((f) => f.id), ['one', 'two']);
      expect(pages, [null, 'page-two']);
    },
  );
}
