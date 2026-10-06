import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

class RemoteReflectionAssistant implements ReflectionAssistant {
  final String baseUrl;
  final String token;

  RemoteReflectionAssistant({
    required this.baseUrl,
    required this.token,
  });

  @override
  Future<String> reflect(String text) async {
    final client = http.Client();
    final root = baseUrl.replaceFirst(RegExp(r'/$'), '');

    try {
      final response = await client
          .post(
            Uri.parse('$root/ai/reflect'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 90));

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid response.');
      }

      if (response.statusCode != 200) {
        throw AssistantException(
          decoded['message'] is String
              ? decoded['message'] as String
              : 'AI assistance is unavailable.',
        );
      }

      final result = decoded['result'];

      if (result is! Map<String, dynamic>) {
        throw const FormatException('Missing result.');
      }

      String field(String key) {
        final value = result[key];

        if (value is! String || value.trim().isEmpty) {
          throw const FormatException('Invalid AI field.');
        }

        return value.trim();
      }

      return 'Possible obstacle\n'
          '${field('obstacle')}\n\n'
          'One small next step\n'
          '${field('nextStep')}\n\n'
          'A question to consider\n'
          '${field('question')}';
    } on TimeoutException {
      throw const AssistantException(
        'The AI request timed out. You can keep writing normally.',
      );
    } on http.ClientException {
      throw const AssistantException(
        'Cannot reach the server. Check your connection.',
      );
    } on FormatException {
      throw const AssistantException(
        'The AI response could not be displayed. Please try again.',
      );
    } finally {
      client.close();
    }
  }
}