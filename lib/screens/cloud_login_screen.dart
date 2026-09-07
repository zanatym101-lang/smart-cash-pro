import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/cloud_auth_service.dart';

class CloudLoginScreen extends StatefulWidget {
  const CloudLoginScreen({super.key});

  @override
  State<CloudLoginScreen> createState() => _CloudLoginScreenState();
}

class _CloudLoginScreenState extends State<CloudLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isLoginMode = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await CloudAuthService.signIn(email, pass);
      } else {
        await CloudAuthService.signUp(email, pass);
      }
      // Auth wrapper in main.dart will automatically redirect on success
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الاتصال بالسحابة: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    bool isSending = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: const Text(
              'إعادة تعيين كلمة المرور',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('أدخل بريدك الإلكتروني المسجل لإرسال رابط إعادة تعيين كلمة المرور:'),
                const SizedBox(height: 12),
                TextField(
                  controller: resetEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: const Icon(Icons.email),
                    border: const OutlineInputBorder(),
                    errorText: dialogError,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSending ? null : () => Navigator.of(dialogCtx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: isSending
                    ? null
                    : () async {
                        final email = resetEmailCtrl.text.trim();
                        if (email.isEmpty) {
                          setDialogState(() => dialogError = 'يرجى إدخال البريد الإلكتروني');
                          return;
                        }
                        setDialogState(() {
                          isSending = true;
                          dialogError = null;
                        });
                        final nav = Navigator.of(dialogCtx);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await CloudAuthService.sendPasswordResetEmail(email);
                          if (!mounted) return;
                          nav.pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF047857),
                              duration: Duration(seconds: 6),
                              content: Text(
                                'تم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك الإلكتروني. يرجى مراجعة صندوق الوارد والبريد غير الهام (Spam).',
                              ),
                            ),
                          );
                        } on FirebaseAuthException catch (e) {
                          String errorMsg;
                          switch (e.code) {
                            case 'user-not-found':
                              errorMsg = 'البريد الإلكتروني غير مسجل لدينا.';
                              break;
                            case 'invalid-email':
                              errorMsg = 'صيغة البريد الإلكتروني غير صحيحة.';
                              break;
                            default:
                              errorMsg = e.message ?? 'حدث خطأ أثناء إرسال الرابط';
                          }
                          setDialogState(() {
                            isSending = false;
                            dialogError = errorMsg;
                          });
                        } catch (e) {
                          setDialogState(() {
                            isSending = false;
                            dialogError = 'حدث خطأ: $e';
                          });
                        }
                      },
                child: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('إرسال الرابط'),
              ),
            ],
          );
        },
      ),
    );
    resetEmailCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoginMode ? 'تسجيل الدخول السحابي' : 'إنشاء مساحة عمل جديدة'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_sync, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 24),
              Text(
                'نظام إدارة المحافظ السحابي',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('سجل دخولك لربط بياناتك بالسحابة ومتابعة فروعك'),
              const SizedBox(height: 32),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
              ),
              if (_isLoginMode) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _isLoading ? null : _showForgotPasswordDialog,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('نسيت كلمة المرور؟'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(_isLoginMode ? 'دخول' : 'إنشاء حساب'),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                child: Text(_isLoginMode ? 'ليس لديك حساب؟ أنشئ مساحة عمل' : 'لديك حساب بالفعل؟ سجل دخول'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
