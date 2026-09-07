import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/monther_ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MontherChatScreen extends StatefulWidget {
  const MontherChatScreen({super.key});

  @override
  State<MontherChatScreen> createState() => _MontherChatScreenState();
}

class _MontherChatScreenState extends State<MontherChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = false;
  bool _isInit = false;
  bool _needsApiKey = false;

  final List<ChatMessage> _messages = [];

  // مفتاح لتتبع آخر يوم تم فيه عرض التقرير
  static const String _lastReportDateKey = 'monther_last_report_date';

  // قائمة الرسائل المحفوظة لحفظها لاحقاً
  final List<Map<String, String>> _savedMessages = [];

  @override
  void initState() {
    super.initState();
    _checkAndInit();
  }

  Future<void> _checkAndInit() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('monther_api_key') ?? '';

    if (key.isEmpty) {
      setState(() => _needsApiKey = true);
      return;
    }

    setState(() => _isLoading = true);

    // تحميل المحادثات السابقة
    final savedHistory = await MontherAiService.instance.loadSavedHistory();

    if (!MontherAiService.instance.isInitialized) {
      MontherAiService.instance.init(key);
    }

    // بدء محادثة جديدة مع تاريخ المحادثات السابقة
    await MontherAiService.instance.startNewChat(
      savedHistory: savedHistory.isNotEmpty ? savedHistory : null,
    );

    // استعادة الرسائل المرئية
    setState(() {
      _messages.clear();
      _savedMessages.clear();

      if (savedHistory.isNotEmpty) {
        for (final msg in savedHistory) {
          final text = msg['text'] ?? '';
          final isUser = msg['role'] == 'user';
          _messages.add(ChatMessage(text: text, isUser: isUser));
          _savedMessages.add(msg);
        }
      }

      _isInit = true;
      _isLoading = false;
    });

    // التقرير اليومي: يظهر مرة واحدة في اليوم فقط
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final lastReport = prefs.getString(_lastReportDateKey) ?? '';
    if (lastReport != todayStr) {
      // لم يُعرض التقرير اليوم بعد
      await prefs.setString(_lastReportDateKey, todayStr);
      _generateAndShowDailyReport();
    } else {
      _scrollToBottom();
    }
  }

  /// توليد وعرض التقرير اليومي
  Future<void> _generateAndShowDailyReport() async {
    setState(() => _isLoading = true);
    final report = await MontherAiService.instance.generateDailyReport();
    if (!mounted) return;

    if (report.isNotEmpty) {
      final reportMsg = ChatMessage(text: report, isUser: false);
      setState(() {
        _messages.add(reportMsg);
        _savedMessages.add({'role': 'model', 'text': report});
        _isLoading = false;
      });
      await MontherAiService.instance.saveHistory(_savedMessages);
    } else {
      setState(() => _isLoading = false);
    }
    _scrollToBottom();
  }

  Future<void> _saveApiKey(String key) async {
    if (key.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('monther_api_key', key.trim());
    setState(() => _needsApiKey = false);
    _checkAndInit();
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final userMsg = {'role': 'user', 'text': text};
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _savedMessages.add(userMsg);
      _isLoading = true;
    });
    _msgController.clear();
    _scrollToBottom();

    final response = await MontherAiService.instance.sendMessage(text);
    final botMsg = {'role': 'model', 'text': response};

    setState(() {
      _messages.add(ChatMessage(text: response, isUser: false));
      _savedMessages.add(botMsg);
      _isLoading = false;
    });

    // حفظ المحادثة بعد كل رسالة
    await MontherAiService.instance.saveHistory(_savedMessages);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('🤖'),
            SizedBox(width: 8),
            Text('المساعد الذكي (منذر)'),
          ],
        ),
        actions: [
          if (!_needsApiKey)
            IconButton(
              tooltip: 'مسح المحادثة',
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('تأكيد'),
                    content: const Text('هل تريد مسح المحادثة والبدء من جديد؟'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('إلغاء'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('مسح'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await MontherAiService.instance.clearHistory();
                  setState(() {
                    _messages.clear();
                    _savedMessages.clear();
                  });
                  // إعادة تهيئة محادثة جديدة نظيفة
                  await MontherAiService.instance.startNewChat();
                  _generateAndShowDailyReport();
                }
              },
            ),
        ],
      ),
      body: _needsApiKey ? _buildApiKeySetup() : _buildChatView(),
    );
  }

  Widget _buildApiKeySetup() {
    final tc = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.smart_toy, size: 80, color: Colors.blueGrey),
          const SizedBox(height: 16),
          const Text(
            'أهلاً بك! أنا "منذر"',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'لكي أتمكن من مساعدتك والعمل بذكاء، يرجى إدخال مفتاح (Gemini API Key) المجاني الخاص بك.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: tc,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _saveApiKey(tc.text),
            child: const Text('حفظ وبدء المحادثة'),
          ),
        ],
      ),
    );
  }

  Widget _buildChatView() {
    if (!_isInit && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return _ChatBubble(message: msg);
            },
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, -2),
                blurRadius: 4,
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: 'اسأل منذر...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.withValues(alpha: 0.1),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser 
              ? Theme.of(context).primaryColor 
              : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 16),
          ),
        ),
        child: isUser
            ? Text(
                message.text,
                style: const TextStyle(color: Colors.white),
              )
            : MarkdownBody(
                data: message.text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: Colors.black87),
                ),
              ),
      ),
    );
  }
}
