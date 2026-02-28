import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GroqService {
  final String _apiKey = dotenv.env['Groq'] ?? '';
  final String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  Future<String?> sendMessage(String message) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json; charset=utf-8', // Added charset
        },
        body: jsonEncode({
          'model': 'openai/gpt-oss-120b',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are a smart agriculture assistant named CropMate. Your goal is to help users with plant care, crop management, disease identification, and gardening advice. You must ONLY answer questions related to plants, crops, farming, soil, weather for agriculture, and related topics. If a user asks about non-agricultural topics (like coding, history, current events, etc.), politely decline and steer the conversation back to plants. You can respond in multiple languages including Malayalam, Hindi, Tamil, Telugu, and English.'
            },
            {'role': 'user', 'content': message}
          ],
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        // Explicitly decode with UTF-8
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'];
      } else {
        print('Groq API Error: ${response.body}');
        return 'Sorry, I encountered an error connecting to the server (${response.statusCode}).';
      }
    } catch (e) {
      print('Groq Service Exception: $e');
      return 'Sorry, I am having trouble connecting right now.';
    }
  }
}