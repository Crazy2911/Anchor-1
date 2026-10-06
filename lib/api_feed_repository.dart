import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'repository.dart';
import 'dart:typed_data';

class ApiFeedRepository extends MemoryAnchorRepository {
  final String baseUrl;
  final String token;

  ApiFeedRepository({
    required this.baseUrl,
    required this.token,
    required super.userId,
  });

  String get _root {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  // ---------------------------------------------------------------------------
  // HTTP REQUESTS
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = http.Client();

    try {
      final request = http.Request(method, Uri.parse('$_root$path'));

      request.headers['Accept'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $token';

      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }

      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(const Duration(seconds: 60));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded['message'];

        throw RepositoryException(
          message is String
              ? message
              : 'The server returned ${response.statusCode}.',
        );
      }

      return decoded;
    } on TimeoutException {
      throw const RepositoryException(
        'The request timed out. Refresh to check the latest server data '
        'before submitting again.',
      );
    } on http.ClientException {
      throw const RepositoryException(
        'Cannot reach the server. Check the connection and reload.',
      );
    } on FormatException {
      throw const RepositoryException(
        'The server returned an unexpected response. '
        'Check that the updated Python server is running.',
      );
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // LOAD ALL ACCOUNT DATA
  // ---------------------------------------------------------------------------

  @override
  Future<AppData> load() async {
    final personalResponse = await _request('GET', '/me/data');
    final communityResponse = await _request('GET', '/posts');
    final socialResponse = await _request('GET', '/me/social');

    try {
      final goals = _list(personalResponse, 'goals').map((value) {
        final map = _object(value);

        return Goal(
          id: _text(map, 'id'),
          title: _text(map, 'title'),
          reason: _text(map, 'reason'),
        );
      }).toList();

      final habits = _list(personalResponse, 'habits').map((value) {
        final map = _object(value);
        final completedOn = map['completedOn'];

        if (completedOn != null && completedOn is! String) {
          throw const FormatException('Invalid completion date.');
        }

        return Habit(
          id: _text(map, 'id'),
          goalId: _text(map, 'goalId'),
          title: _text(map, 'title'),
          completedOn: completedOn as String?,
        );
      }).toList();

      final reflections = _list(personalResponse, 'reflections').map((value) {
        final map = _object(value);

        return Reflection(
          id: _text(map, 'id'),
          title: _text(map, 'title'),
          body: _text(map, 'body'),
          mood: _text(map, 'mood'),
        );
      }).toList();

      final profileMap = _object(personalResponse['profile']);

      final profile = UserProfile(
        name: _text(profileMap, 'name'),
        bio: _optionalText(profileMap, 'bio'),
        region: _optionalText(profileMap, 'region'),
      );

      final posts = _list(
        communityResponse,
        'posts',
      ).map<CommunityPost>(_parsePost).toList();

      final savedIds = _stringSet(socialResponse, 'savedPostIds');

      final helpfulIds = _stringSet(socialResponse, 'helpfulPostIds');

      final followedTopics = _stringSet(socialResponse, 'followedTopics');

      // Change cached data only after all three responses parse successfully.
      replacePersonalData(
        goals: goals,
        habits: habits,
        reflections: reflections,
        profile: profile,
      );

      replaceSocialData(
        savedPostIds: savedIds,
        helpfulPostIds: helpfulIds,
        followedTopics: followedTopics,
      );

      replaceCommunityPosts(posts);
    } on FormatException {
      throw const RepositoryException(
        'The server returned an unexpected record format.',
      );
    }

    return super.load();
  }

  Future<String> uploadPostImage(Uint8List bytes, String contentType) async {
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw const RepositoryException(
        'Choose a non-empty image no larger than 2 MiB.',
      );
    }

    final client = http.Client();

    try {
      final response = await client
          .post(
            Uri.parse('$_root/me/images'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': contentType,
              'Accept': 'application/json',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 90));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid upload response.');
      }

      if (response.statusCode != 201) {
        throw RepositoryException(
          decoded['message'] is String
              ? decoded['message'] as String
              : 'The image could not be uploaded.',
        );
      }

      final imageId = decoded['imageId'];

      if (imageId is! String || imageId.isEmpty) {
        throw const FormatException('Missing image ID.');
      }

      return imageId;
    } on TimeoutException {
      throw const RepositoryException(
        'Image upload timed out. Your draft is still here. Try again.',
      );
    } on http.ClientException {
      throw const RepositoryException(
        'Cannot reach the server to upload your image.',
      );
    } on FormatException {
      throw const RepositoryException(
        'The server returned an invalid image upload response.',
      );
    } finally {
      client.close();
    }
  }

  Future<void> setPostImage(String postId, String? imageId) async {
    await _request(
      'PUT',
      '/posts/${Uri.encodeComponent(postId)}/image',
      body: {'imageId': imageId},
    );
  }

  // ---------------------------------------------------------------------------
  // COMMUNITY POSTS — THESE MUST WRITE TO THE SERVER
  // ---------------------------------------------------------------------------
  Future<String?> getPostImageUrl(String postId) async {
    final response = await _request(
      'GET',
      '/posts/${Uri.encodeComponent(postId)}/image',
    );

    final value = response['imageUrl'];

    if (value == null) return null;

    if (value is! String) {
      throw const RepositoryException(
        'The server returned an invalid image link.',
      );
    }

    final uri = Uri.tryParse(value);

    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const RepositoryException(
        'The server returned an invalid image link.',
      );
    }

    return value;
  }

  @override
  Future<void> savePost(CommunityPost post) async {
    await _request(
      'PUT',
      '/posts/${Uri.encodeComponent(post.id)}',
      body: {'title': post.title, 'body': post.body, 'topic': post.topic},
    );
  }

  @override
  Future<void> deletePost(String id) async {
    await _request('DELETE', '/posts/${Uri.encodeComponent(id)}');
  }

  @override
  Future<void> addComment(String postId, CommunityComment comment) async {
    await _request(
      'PUT',
      '/posts/${Uri.encodeComponent(postId)}'
          '/comments/${Uri.encodeComponent(comment.id)}',
      body: {'body': comment.body, 'parentId': comment.parentId},
    );
  }

  // The authenticated backend supplies author ID and display name.

  // ---------------------------------------------------------------------------
  // GOALS
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveGoal(Goal goal) async {
    await _request(
      'PUT',
      '/me/goals/${Uri.encodeComponent(goal.id)}',
      body: {'title': goal.title, 'reason': goal.reason},
    );
  }

  @override
  Future<void> deleteGoal(String id) async {
    await _request('DELETE', '/me/goals/${Uri.encodeComponent(id)}');
  }

  // ---------------------------------------------------------------------------
  // HABITS
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveHabit(Habit habit) async {
    await _request(
      'PUT',
      '/me/habits/${Uri.encodeComponent(habit.id)}',
      body: {
        'goalId': habit.goalId,
        'title': habit.title,
        'completedOn': habit.completedOn,
      },
    );
  }

  @override
  Future<void> deleteHabit(String id) async {
    await _request('DELETE', '/me/habits/${Uri.encodeComponent(id)}');
  }

  // ---------------------------------------------------------------------------
  // REFLECTIONS
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveReflection(Reflection reflection) async {
    await _request(
      'PUT',
      '/me/reflections/${Uri.encodeComponent(reflection.id)}',
      body: {
        'title': reflection.title,
        'body': reflection.body,
        'mood': reflection.mood,
      },
    );
  }

  @override
  Future<void> deleteReflection(String id) async {
    await _request('DELETE', '/me/reflections/${Uri.encodeComponent(id)}');
  }

  // ---------------------------------------------------------------------------
  // PROFILE
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveProfile(UserProfile profile) async {
    await _request(
      'PUT',
      '/me/profile',
      body: {
        'name': profile.name,
        'bio': profile.bio,
        'region': profile.region,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SAVES, REACTIONS, AND TOPIC FOLLOWING
  // ---------------------------------------------------------------------------

  Future<void> _setPreference({
    required String kind,
    required String target,
    required bool enabled,
  }) async {
    await _request(
      'PUT',
      '/me/social',
      body: {'kind': kind, 'target': target, 'enabled': enabled},
    );
  }

  @override
  Future<void> toggleSaved(String postId) async {
    final current = await super.load();

    await _setPreference(
      kind: 'save',
      target: postId,
      enabled: !current.savedPostIds.contains(postId),
    );
  }

  @override
  Future<void> toggleHelpful(String postId) async {
    final current = await super.load();

    await _setPreference(
      kind: 'helpful',
      target: postId,
      enabled: !current.helpfulPostIds.contains(postId),
    );
  }

  @override
  Future<void> toggleTopic(String topic) async {
    final current = await super.load();

    await _setPreference(
      kind: 'topic',
      target: topic,
      enabled: !current.followedTopics.contains(topic),
    );
  }

  @override
  Future<void> reportPost(ContentReport report) async {
    await _request(
      'PUT',
      '/me/reports/${Uri.encodeComponent(report.postId)}',
      body: {'reason': report.reason},
    );
  }

  // ---------------------------------------------------------------------------
  // JSON PARSING
  // ---------------------------------------------------------------------------

  CommunityPost _parsePost(dynamic value) {
    final map = _object(value);
    final comments = map['comments'] ?? [];

    if (comments is! List) {
      throw const FormatException('Expected a comments list.');
    }

    return CommunityPost(
      id: _text(map, 'id'),
      authorId: _text(map, 'authorId'),
      author: _text(map, 'author'),
      title: _text(map, 'title'),
      body: _text(map, 'body'),
      topic: _text(map, 'topic'),
      comments: comments.map<CommunityComment>(_parseComment).toList(),
    );
  }

  CommunityComment _parseComment(dynamic value) {
    final map = _object(value);
    final parentId = map['parentId'];

    if (parentId != null && parentId is! String) {
      throw const FormatException('Invalid parent ID.');
    }

    return CommunityComment(
      id: _text(map, 'id'),
      authorId: _text(map, 'authorId'),
      author: _text(map, 'author'),
      body: _text(map, 'body'),
      parentId: parentId as String?,
    );
  }

  Map<String, dynamic> _object(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected an object.');
    }

    return value;
  }

  List<dynamic> _list(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value is! List) {
      throw FormatException('Expected a list for $key.');
    }

    return value;
  }

  Set<String> _stringSet(Map<String, dynamic> map, String key) {
    final values = _list(map, key);

    if (values.any((value) => value is! String)) {
      throw FormatException('Expected text values for $key.');
    }

    return values.cast<String>().toSet();
  }

  String _text(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid field: $key');
    }

    return value;
  }

  String _optionalText(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value is! String) {
      throw FormatException('Expected text for $key.');
    }

    return value;
  }
}
