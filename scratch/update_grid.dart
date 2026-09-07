import 'dart:io';

void main() {
  final file = File('lib/screens/dashboard_screen.dart');
  var content = file.readAsStringSync();

  // Change crossAxisCount for the action grid
  // Original:
  // int cross = 2;
  // if (width >= 900) { cross = 4; } else if (width >= 600) { cross = 3; } else { cross = 2; }
  content = content.replaceFirst(
    '''
        int cross = 2;
        if (width >= 900) {
          cross = 4;
        } else if (width >= 600) {
          cross = 3;
        } else {
          cross = 2;
        }''',
    '''
        int cross = 3;
        if (width >= 900) {
          cross = 6;
        } else if (width >= 600) {
          cross = 4;
        } else {
          cross = 3;
        }''',
  );

  // If the string replacement above fails because of formatting, try regex
  content = content.replaceAll(RegExp(r'childAspectRatio: width < 360 \? 1.05 : 1.0,'), 'childAspectRatio: 1.1,');

  file.writeAsStringSync(content);
}
