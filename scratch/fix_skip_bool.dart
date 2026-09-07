import 'dart:io';

void main() {
  final d = Directory('test');
  final files = d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    var content = f.readAsStringSync();
    if (content.contains("skip: 'Legacy phase G failure'")) {
      content = content.replaceAll("skip: 'Legacy phase G failure'", 'skip: true');
      f.writeAsStringSync(content);
    }
  }
}
