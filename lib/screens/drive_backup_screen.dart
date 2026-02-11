import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../services/drive_backup_service.dart';

class DriveBackupScreen extends StatefulWidget {
  const DriveBackupScreen({super.key});

  @override
  State<DriveBackupScreen> createState() => _DriveBackupScreenState();
}

class _DriveBackupScreenState extends State<DriveBackupScreen> {
  bool _loading = true;
  String? _email;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _email = await DriveBackupService.instance.currentEmail();
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    if (!_isMobile) return;
    setState(() => _working = true);
    try {
      final acc = await DriveBackupService.instance.signIn();
      if (!mounted) return;
      setState(() => _email = acc?.email);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تسجيل الدخول: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _working = true);
    try {
      await DriveBackupService.instance.signOut();
      if (!mounted) return;
      setState(() => _email = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تسجيل الخروج: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _uploadNow() async {
    if (!_isMobile) return;
    setState(() => _working = true);
    try {
      final id = await DriveBackupService.instance.uploadLatestBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم رفع النسخة إلى Drive (ID: $id)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الرفع: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _email != null && _email!.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'Google Drive'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('النسخ الاحتياطي على Google Drive', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          if (!_isMobile)
                            const Text('متاح على Android/iOS فقط.')
                          else ...[
                            Text(signedIn ? 'تم تسجيل الدخول: $_email' : 'غير مسجل الدخول'),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: (_working || signedIn) ? null : _signIn,
                                  icon: const Icon(Icons.login),
                                  label: const Text('تسجيل الدخول'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: (_working || !signedIn) ? null : _signOut,
                                  icon: const Icon(Icons.logout),
                                  label: const Text('تسجيل الخروج'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: (_working || !signedIn) ? null : _uploadNow,
                                  icon: const Icon(Icons.cloud_upload),
                                  label: const Text('رفع نسخة الآن'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'ملاحظة: لتفعيل Google Drive بالكامل، يلزم إعداد OAuth '
                        'للأندرويد والآيفون (Client ID).',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
