// Prints a CycloneDX 1.4 SBOM (JSON) of this app's pub dependencies to stdout,
// for attaching to GitHub Releases: `dart run tool/sbom.dart > dist/SBOM.cdx.json`.
//
// Kept dependency-free and read-only so it can run anywhere `dart` exists.
import 'dart:convert';
import 'dart:io';

void main() {
  final lock = File('pubspec.lock').readAsLinesSync();
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final version = pubspec
      .firstWhere((l) => l.startsWith('version:'))
      .split(':')[1]
      .trim()
      .split('+')
      .first;

  // pubspec.lock: a package's version line always follows its name line.
  final components = <Map<String, Object?>>[];
  var name = '';
  for (final line in lock) {
    if (line.startsWith('  ') && !line.startsWith('    ') && line.trim().endsWith(':')) {
      name = line.trim().substring(0, line.trim().length - 1);
    } else if (line.startsWith('    version:') && name.isNotEmpty) {
      components.add({
        'type': 'library',
        'name': name,
        'version': line.split('"')[1],
        'purl': 'pkg:pub/$name@${line.split('"')[1]}',
      });
      name = '';
    }
  }

  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'bomFormat': 'CycloneDX',
    'specVersion': '1.4',
    'serialNumber': 'urn:uuid:00000000-0000-0000-0000-000000000000',
    'version': 1,
    'metadata': {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'tools': [
        {'vendor': 'chess-coach', 'name': 'tool/sbom.dart'},
      ],
      'component': {
        'type': 'application',
        'name': 'chess_coach',
        'version': version,
        'purl': 'pkg:pub/chess_coach@$version',
      },
    },
    'components': components,
  }));
}
