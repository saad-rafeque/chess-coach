import 'dart:async';

import 'package:chess_coach/app/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ota_update/ota_update.dart';

void main() {
  late StreamController<OtaEvent> events;
  late Updater updater;
  var starts = 0;
  setUp(() {
    events = StreamController<OtaEvent>();
    starts = 0;
    updater =
        Updater(
            kind: InstallKind.android,
            androidTimeout: const Duration(milliseconds: 40),
            androidEvents: (_, _, _) {
              starts++;
              return events.stream;
            },
          )
          ..available = const ReleaseInfo(
            version: '9.9.9',
            notes: '',
            pageUrl: '',
            asset: (
              name: 'update.apk',
              url: 'https://example.test/update.apk',
              size: 1,
            ),
            sha256: 'checksum',
          );
  });
  tearDown(() async {
    updater.dispose();
    await events.close();
  });
  Future<void> emit(OtaStatus status, [String? value]) async {
    events.add(OtaEvent(status, value));
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'installer cancellation keeps the update available and allows retry',
    () async {
      final installing = updater.install();
      await emit(OtaStatus.INSTALLING);
      expect(updater.status, UpdateStatus.installing);
      expect(updater.available, isNotNull);
      await emit(OtaStatus.INSTALLATION_ERROR);
      await installing;
      expect(updater.status, UpdateStatus.failed);
      expect(updater.available, isNotNull);
      expect(updater.error, contains('not installed'));
    },
  );

  test('only confirmed installation clears the offered update', () async {
    final installing = updater.install();
    await emit(OtaStatus.INSTALLING);
    expect(updater.available, isNotNull);
    await emit(OtaStatus.INSTALLATION_DONE);
    await installing;
    expect(updater.available, isNull);
    expect(updater.status, UpdateStatus.idle);
  });

  test('closed install stream fails with retry instead of hanging', () async {
    final installing = updater.install();
    await emit(OtaStatus.INSTALLING);
    await events.close();
    await installing;
    expect(updater.status, UpdateStatus.failed);
    expect(updater.available, isNotNull);
  });

  test('installer timeout remains active after INSTALLING', () async {
    final installing = updater.install();
    await emit(OtaStatus.INSTALLING);
    await installing;
    expect(updater.status, UpdateStatus.failed);
    expect(updater.error, contains('did not finish'));
    expect(updater.available, isNotNull);
  });

  test('duplicate install request cannot start another download', () async {
    final installing = updater.install();
    await updater.install();
    expect(starts, 1);
    await emit(OtaStatus.CANCELED);
    await installing;
  });

  test('invalid progress cannot poison the progress bar', () async {
    final installing = updater.install();
    await emit(OtaStatus.DOWNLOADING, 'NaN');
    expect(updater.progress, 0);
    await emit(OtaStatus.DOWNLOADING, '300');
    expect(updater.progress, 1);
    await emit(OtaStatus.CANCELED);
    await installing;
  });
}
