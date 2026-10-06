import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

class SummaryItem {
  final String text;
  final List<String> commentIds;

  const SummaryItem({
    required this.text,
    required this.commentIds,
  });
}

class DiscussionSummary {
  final String summary;
  final List<SummaryItem> suggestions;
  final List<SummaryItem> outcomes;
  final int includedCount;
  final int totalCount;

  const DiscussionSummary({
    required this.summary,
    required this.suggestions,
    required this.outcomes,
    required this.includedCount,
    required this.totalCount,
  });
}

abstract class DiscussionAssistant {
  Future<DiscussionSummary> summarize(String postId);
}

class RemoteDiscussionAssistant implements DiscussionAssistant {
  final String baseUrl;
  final String token;

  RemoteDiscussionAssistant({
    required this.baseUrl,
    required this.token,
  });

  @override
  Future<DiscussionSummary> summarize(String postId) async {
    final client = http.Client();
    final root = baseUrl.replaceFirst(RegExp(r'/$'), '');

    try {
      final response = await client
          .post(
            Uri.parse('$root/ai/summarize-discussion'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'postId': postId}),
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
              : 'Discussion summary is unavailable.',
        );
      }

      final summary = decoded['summary'];
      final included = decoded['includedCommentCount'];
      final total = decoded['totalCommentCount'];

      if (summary is! String ||
          included is! int ||
          total is! int ||
          included < 0 ||
          total < included) {
        throw const FormatException('Invalid summary data.');
      }

      List<SummaryItem> parseItems(String key) {
        final values = decoded[key];

        if (values is! List) {
          throw const FormatException('Invalid summary items.');
        }

        return values.map<SummaryItem>((value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Invalid summary item.');
          }

          final text = value['text'];
          final ids = value['commentIds'];

          if (text is! String ||
              ids is! List ||
              ids.any((id) => id is! String)) {
            throw const FormatException('Invalid summary reference.');
          }

          return SummaryItem(
            text: text,
            commentIds: ids.cast<String>().toList(),
          );
        }).toList();
      }

      return DiscussionSummary(
        summary: summary,
        suggestions: parseItems('suggestions'),
        outcomes: parseItems('reportedOutcomes'),
        includedCount: included,
        totalCount: total,
      );
    } on TimeoutException {
      throw const AssistantException(
        'The summary timed out. You can still read the discussion.',
      );
    } on http.ClientException {
      throw const AssistantException('Cannot reach the server.');
    } on FormatException {
      throw const AssistantException(
        'The summary could not be displayed.',
      );
    } finally {
      client.close();
    }
  }
}