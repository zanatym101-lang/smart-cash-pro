import 'dart:io';

void main() {
  final file = File('lib/screens/dashboard_screen.dart');
  var content = file.readAsStringSync();

  // 1. Add import
  if (!content.contains('monther_chat_screen.dart')) {
    content = content.replaceFirst(
      "import 'dart:async';", 
      "import 'dart:async';\nimport 'monther_chat_screen.dart';"
    );
  }

  // 2. Add FloatingActionButton inside Scaffold
  if (!content.contains('floatingActionButton:')) {
    content = content.replaceFirst(
      '      body: SafeArea(',
      '''
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MontherChatScreen()),
          );
        },
        backgroundColor: Theme.of(context).primaryColor,
        child: const Text('🤖', style: TextStyle(fontSize: 24)),
      ),
      body: SafeArea('''
    );
  }

  file.writeAsStringSync(content);
}
