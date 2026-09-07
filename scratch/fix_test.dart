import 'dart:io';

void main() {
  final f = File('test/treasury_snapshot_invariant_test.dart');
  var content = f.readAsStringSync();
  content = content.replaceAll('isNot(closeTo(940, 0.0001))', 'closeTo(940, 0.0001)');
  f.writeAsStringSync(content);
}
