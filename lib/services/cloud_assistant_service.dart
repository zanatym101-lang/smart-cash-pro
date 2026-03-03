import 'dart:convert';

import 'package:http/http.dart' as http;

class CloudAssistantService {
  static const String _endpoint =
      'https://smart-cash-pro-six.vercel.app/api/assistant';

  static Future<String> ask(Map<String, dynamic> payload) async {
    final res = await http.post(
      Uri.parse(_endpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('فشل الاتصال بالسحابة (${res.statusCode})');
    }

    final data = jsonDecode(res.body);
    final answer = data is Map ? data['answer']?.toString() : null;
    if (answer == null || answer.trim().isEmpty) {
      throw Exception('لم يتم استلام رد من المساعد');
    }
    return answer.trim();
  }
}
