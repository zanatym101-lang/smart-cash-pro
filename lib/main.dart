import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/branding.dart';
import 'screens/admin_gate_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const KingWalletApp());
}

class KingWalletApp extends StatelessWidget {
  const KingWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBranding.nameFull,
      theme: AppTheme.light(),
      home: const AdminGateScreen(),
    );
  }
}
