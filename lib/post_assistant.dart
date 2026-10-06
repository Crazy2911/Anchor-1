import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'repository.dart';

class PostSuggestion {
  final String title;
  final String body;
  final String topic;

  const PostSuggestion({
    required this.title,
    required this.body,
    required this.topic,
  });
}

abstract class PostAssistant {
  Future<PostSuggestion> improve({
    required String title,
    required String body,
    required String topic,
  });
}

class RemotePostAssistant implements PostAssistant {
  final String baseUrl;
  final String token;

  RemotePostAssistant({
    required this.baseUrl,
    required this.token,
  });

  @override
  Future<PostSuggestion> improve({
    required String title,
    required String body,
    required String topic,
  }) async {
    final client = http.Client();
    final root = baseUrl.replaceFirst(RegExp(r'/$'), '');

    try {
      final response = await client
          .post(
            Uri.parse('$root/ai/improve-post'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'title': title,
              'body': body,
              'topic': topic,
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
              : 'Post assistance is unavailable.',
        );
      }

      final result = decoded['result'];

      if (result is! Map<String, dynamic>) {
        throw const FormatException('Missing suggestion.');
      }

      String field(String name, int minimum, int maximum) {
        final value = result[name];

        if (value is! String) {
          throw const FormatException('Invalid suggestion field.');
        }

        final text = value.trim();

        if (text.length < minimum || text.length > maximum) {
          throw const FormatException('Invalid suggestion length.');
        }

        return text;
      }

      final suggestedTitle = field('title', 3, 100);
      final suggestedBody = field('body', 10, 3000);
      final suggestedTopic = field('topic', 1, 80);

      if (!topics.contains(suggestedTopic)) {
        throw const FormatException('Unsupported topic.');
      }

      return PostSuggestion(
        title: suggestedTitle,
        body: suggestedBody,
        topic: suggestedTopic,
      );
    } on TimeoutException {
      throw const AssistantException(
        'AI timed out. Your post is unchanged.',
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