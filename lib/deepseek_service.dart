import 'package:http/http.dart' as http;
import 'dart:convert';

class DeepSeekHelper {
  // ВСТАВЬ СЮДА СВОЙ КЛЮЧ!
  static const String apiKey = 'sk-3365970381904737bf95b76f3daf651c';
  
  static const String apiUrl = 'https://api.deepseek.com/v1/chat/completions';
  
  static Future<String> askQuestion(String question) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'user', 'content': question}
          ]
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return 'Ошибка: ${response.statusCode}';
      }
    } catch (e) {
      return 'Ошибка соединения: $e';
    }
  }
}