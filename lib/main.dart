import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/env_config.dart';
import 'core/theme.dart';
import 'core/branding.dart';
import 'data/app_db.dart';
import 'screens/admin_gate_screen.dart';
import 'screens/cloud_login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/cloud_sync_service.dart';
import 'services/notification_service.dart';
import 'services/app_integrity_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  EnvConfig.load();
  EnvConfig.debugLogCurrentEnv();
  try {
    await MobileAds.instance.initialize();
  } catch (e) {
    debugPrint('MobileAds init failed: $e');
  }
  await NotificationService.init();
  runApp(const KingWalletApp());
}

class KingWalletApp extends StatelessWidget {
  const KingWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBranding.nameFull,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const RootGateScreen(),
    );
  }
}

class RootGateScreen extends StatefulWidget {
  const RootGateScreen({super.key});

  @override
  State<RootGateScreen> createState() => _RootGateScreenState();
}

class _RootGateScreenState extends State<RootGateScreen> {
  late final Future<bool> _integrityFuture;

  @override
  void initState() {
    super.initState();
    _integrityFuture = AppIntegrityService.verifyAppIntegrity();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _integrityFuture,
      builder: (context, integritySnapshot) {
        if (integritySnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isIntact = integritySnapshot.data ?? true;
        if (!isIntact) {
          return const TamperAlertScreen();
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasData) {
              final uid = snapshot.data!.uid;
              AppDb.instance.tryAutoActivateFromCloud();
              CloudSyncService.startSync(uid);
              return const AdminGateScreen(); // Logged into cloud, proceed to local PIN gate
            }
            CloudSyncService.stopSync();
            return const CloudLoginScreen(); // Needs cloud login
          },
        );
      },
    );
  }
}