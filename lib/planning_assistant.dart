import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

class PlanSuggestion {
  final String title;
  final String reason;

  const PlanSuggestion({
    required this.title,
    required this.reason,
  });
}

abstract class PlanningAssistant {
  Future<PlanSuggestion> suggest({
    required String task,
    required String text,
    String? goalId,
  });
}

class RemotePlanningAssistant implements PlanningAssistant {
  final String baseUrl;
  final String token;

  RemotePlanningAssistant({
    required this.baseUrl,
    required this.token,
  });

  @override
  Future<PlanSuggestion> suggest({
    required String task,
    required String text,
    String? goalId,
  }) async {
    final client = http.Client();
    final root = baseUrl.replaceFirst(RegExp(r'/$'), '');

    try {
      final response = await client
          .post(
            Uri.parse('$root/ai/plan'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'task': task,
              'text': text,
              'goalId': ?goalId,
            }),
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
              : 'AI planning is unavailable.',
        );
      }

      final result = decoded['result'];

      if (result is! Map<String, dynamic>) {
        throw const FormatException('Missing suggestion.');
      }

      final title = result['title'];
      final reason = result['reason'];

      if (title is! String || reason is! String) {
        throw const FormatException('Invalid suggestion.');
      }

      if (title.trim().length < 3 ||
          title.trim().length > 100 ||
          reason.trim().length < 10 ||
          reason.trim().length > 800) {
        throw const FormatException('Invalid suggestion length.');
      }

      return PlanSuggestion(
        title: title.trim(),
        reason: reason.trim(),
      );
    } on TimeoutException {
      throw const AssistantException(
        'AI timed out. You can continue editing normally.',
      );
    } on http.ClientException {
      throw const AssistantException(
        'Cannot reach the server.',
      );
    } on FormatException {
      throw const AssistantException(
        'The suggestion could not be displayed.',
      );
    } finally {
      client.close();
    }
  }
}