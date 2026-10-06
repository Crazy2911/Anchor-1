import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

class FocusSuggestion {
  final String habitId;
  final String title;
  final String reason;

  const FocusSuggestion({
    required this.habitId,
    required this.title,
    required this.reason,
  });
}

abstract class FocusAssistant {
  Future<FocusSuggestion> suggest(List<String> habitIds);
}

class RemoteFocusAssistant implements FocusAssistant {
  final String baseUrl;
  final String token;

  RemoteFocusAssistant({
    required this.baseUrl,
    required this.token,
  });

  @override
  Future<FocusSuggestion> suggest(List<String> habitIds) async {
    final client = http.Client();
    final root = baseUrl.replaceFirst(RegExp(r'/$'), '');

    try {
      final response = await client
          .post(
            Uri.parse('$root/ai/next-action'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'habitIds': habitIds}),
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
              : 'AI could not suggest a next action.',
        );
      }

      final id = decoded['habitId'];
      final title = decoded['title'];
      final reason = decoded['reason'];

      if (id is! String ||
          title is! String ||
          reason is! String ||
          !habitIds.contains(id) ||
          title.trim().isEmpty ||
          reason.trim().isEmpty) {
        throw const FormatException('Invalid suggestion.');
      }

      return FocusSuggestion(
        habitId: id,
        title: title,
        reason: reason,
      );
    } on TimeoutException {
      throw const AssistantException(
        'AI timed out. You can choose a habit yourself.',
      );
    } on http.ClientException {
      throw const AssistantException('Cannot reach the server.');
    } on FormatException {
      throw const AssistantException(
        'The suggestion could not be displayed.',
      );
    } finally {
      client.close();
    }
  }
}