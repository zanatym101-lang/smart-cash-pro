import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source files do not contain mojibake fragments', () {
    final bannedFragments = <String>[
      String.fromCharCodes([0x0637, 0x00A7]),
      String.fromCharCodes([0x0637, 0x00B9]),
      String.fromCharCodes([0x0637, 0x00B3]),
      String.fromCharCodes([0x0638, 0x201E]),
      String.fromCharCodes([0x0638, 0x2026]),
      String.fromCharCodes([0x0638, 0x2020]),
      String.fromCharCodes([0x0638, 0x0679]),
      String.fromCharCodes([0x0638, 0x2021]),
      String.fromCharCode(0x00C3),
      String.fromCharCode(0x00C2),
      String.fromCharCodes([0x00E2, 0x20AC]),
      String.fromCharCode(0xFFFD),
    ];

    final findings = <String>[];
    final roots = ['lib', 'test'];

    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;

        final content = entity.readAsStringSync();
        for (final fragment in bannedFragments) {
          if (content.contains(fragment)) {
            findings.add('${entity.path}: contains [$fragment]');
          }
        }
      }
    }

    expect(
      findings,
      isEmpty,
      reason: findings.isEmpty
          ? null
          : 'Corrupted text fragments found:\n${findings.join('\n')}',
    );
  });
}
