import 'dart:io';

void main() {
  final f = File('android/app/build.gradle.kts');
  var content = f.readAsStringSync();
  content = content.replaceFirst(
    'android {',
    'android {\n    lint {\n        checkReleaseBuilds = false\n    }',
  );
  f.writeAsStringSync(content);
}
