import 'models.dart';

// Phase 2: implement this interface using REST services.
// Screens do not need to know which implementation is being used.
abstract class AnchorRepository {
  Future<AppData> load();

  Future<void> saveGoal(Goal goal);
  Future<void> deleteGoal(String id);

  Future<void> saveHabit(Habit habit);
  Future<void> deleteHabit(String id);

  Future<void> saveReflection(Reflection reflection);
  Future<void> deleteReflection(String id);

  Future<void> savePost(CommunityPost post);
  Future<void> deletePost(String id);
  Future<void> addComment(String postId, CommunityComment comment);

  Future<void> toggleSaved(String postId);
  Future<void> toggleHelpful(String postId);
  Future<void> toggleTopic(String topic);

  Future<void> saveProfile(UserProfile profile);
  Future<void> reportPost(ContentReport report);
}

class RepositoryException implements Exception {
  final String message;

  const RepositoryException(this.message);

  @override
  String toString() => message;
}

class MemoryAnchorRepository implements AnchorRepository {
  final String userId;

  MemoryAnchorRepository({this.userId = currentUserId});
  bool failNextRequest = false;
  void replaceSocialData({
  required Set<String> savedPostIds,
  required Set<String> helpfulPostIds,
  required Set<String> followedTopics,
}) {
  _saved
    ..clear()
    ..addAll(savedPostIds);

  _helpful
    ..clear()
    ..addAll(helpfulPostIds);

  _followed
    ..clear()
    ..addAll(followedTopics);
}
  void replacePersonalData({
  required List<Goal> goals,
  required List<Habit> habits,
  required List<Reflection> reflections,
  required UserProfile profile,
}) {
  _goals
    ..clear()
    ..addAll(goals);

  _habits
    ..clear()
    ..addAll(habits);

  _reflections
    ..clear()
    ..addAll(reflections);

  _profile = profile;
}

  final List<Goal> _goals = [
    const Goal(
      id: 'g1',
      title: 'Learn Flutter',
      reason: 'Build an application I understand from start to finish.',
    ),
    const Goal(
      id: 'g2',
      title: 'Read consistently',
      reason: 'Make space for learning beyond my coursework.',
    ),
  ];

  final List<Habit> _habits = [
    const Habit(id: 'h1', goalId: 'g1', title: 'Practice Dart for 20 minutes'),
    const Habit(id: 'h2', goalId: 'g2', title: 'Read five pages'),
  ];

  final List<Reflection> _reflections = [];

  final List<CommunityPost> _posts = [
    CommunityPost(
      id: 'p1',
      authorId: 'sample-maya',
      author: 'Maya · sample profile',
      title: 'How do you restart after missing a few days?',
      body:
          'I was practicing regularly, but a busy week interrupted '
          'my routine. What helps you restart without trying to '
          'catch up on everything at once?',
      topic: 'Study routines',
      comments: const [
        CommunityComment(
          id: 'c1',
          authorId: 'sample-luis',
          author: 'Luis · sample profile',
          body:
              'I restart with a five-minute session. '
              'Making the first step smaller helps me.',
        ),
      ],
    ),
    CommunityPost(
      id: 'p2',
      authorId: 'sample-jules',
      author: 'Jules · sample profile',
      title: 'A small change that helped my drawing practice',
      body:
          'I leave my sketchbook open on my desk. '
          'It makes starting easier. What changes have helped '
          'you make room for creative work?',
      topic: 'Creative practice',
    ),
    CommunityPost(
      id: 'p3',
      authorId: 'sample-sam',
      author: 'Sam · sample profile',
      title: 'Looking for a better evening phone routine',
      body:
          'I often open my phone without a clear reason. '
          'I would like to try one manageable change this week. '
          'What have you tried, and what happened?',
      topic: 'Digital habits',
    ),
  ];

  final Set<String> _saved = {};
  final Set<String> _helpful = {};
  final Set<String> _followed = {};
  final List<ContentReport> _reports = [];

  UserProfile _profile = const UserProfile(
    name: 'Anchor Explorer',
    bio: 'Learning to make progress through small actions.',
    region: '',
  );

  // Community posts now come entirely from the server.
  // Goals, habits, reflections and profile remain untouched.
  void replaceCommunityPosts(List<CommunityPost> posts) {
    _posts
      ..clear()
      ..addAll(posts);

    final existingIds = posts.map((post) => post.id).toSet();

    _saved.removeWhere((id) => !existingIds.contains(id));
    _helpful.removeWhere((id) => !existingIds.contains(id));
  }

  Future<void> _wait() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (failNextRequest) {
      failNextRequest = false;
      throw const RepositoryException(
        'Simulated request failure. Please try again.',
      );
    }
  }

  void _replace<T>(List<T> list, T value, String id, String Function(T) getId) {
    final index = list.indexWhere((item) => getId(item) == id);

    if (index == -1) {
      list.insert(0, value);
    } else {
      list[index] = value;
    }
  }

  CommunityPost _requirePost(String id) {
    final post = findById(_posts, id, (post) => post.id);

    if (post == null) {
      throw const RepositoryException('This post no longer exists.');
    }

    return post;
  }

  void _toggle(Set<String> items, String id) {
    if (!items.remove(id)) items.add(id);
  }

  @override
  Future<AppData> load() async {
    await _wait();

    return AppData(
      goals: _goals,
      habits: _habits,
      reflections: _reflections,
      posts: _posts,
      savedPostIds: _saved,
      helpfulPostIds: _helpful,
      followedTopics: _followed,
      profile: _profile,
    );
  }

  @override
  Future<void> saveGoal(Goal goal) async {
    await _wait();
    _replace(_goals, goal, goal.id, (item) => item.id);
  }

  @override
  Future<void> deleteGoal(String id) async {
    await _wait();
    _goals.removeWhere((goal) => goal.id == id);
    _habits.removeWhere((habit) => habit.goalId == id);
  }

  @override
  Future<void> saveHabit(Habit habit) async {
    await _wait();

    if (!_goals.any((goal) => goal.id == habit.goalId)) {
      throw const RepositoryException('Choose an existing goal.');
    }

    _replace(_habits, habit, habit.id, (item) => item.id);
  }

  @override
  Future<void> deleteHabit(String id) async {
    await _wait();
    _habits.removeWhere((habit) => habit.id == id);
  }

  @override
  Future<void> saveReflection(Reflection reflection) async {
    await _wait();
    _replace(_reflections, reflection, reflection.id, (item) => item.id);
  }

  @override
  Future<void> deleteReflection(String id) async {
    await _wait();
    _reflections.removeWhere((reflection) => reflection.id == id);
  }

  @override
  Future<void> savePost(CommunityPost post) async {
    await _wait();

    final existing = findById(_posts, post.id, (item) => item.id);

    if (post.authorId != userId ||
        (existing != null && existing.authorId != userId)) {
      throw const RepositoryException('You can only edit your own posts.');
    }

    _replace(_posts, post, post.id, (item) => item.id);
  }

  @override
  Future<void> deletePost(String id) async {
    await _wait();
    final post = _requirePost(id);

    if (post.authorId != userId) {
      throw const RepositoryException('You can only delete your own posts.');
    }

    _posts.removeWhere((item) => item.id == id);
    _saved.remove(id);
    _helpful.remove(id);
  }

  @override
  Future<void> addComment(String postId, CommunityComment comment) async {
    await _wait();
    final post = _requirePost(postId);

    if (comment.parentId != null &&
        !post.comments.any((item) => item.id == comment.parentId)) {
      throw const RepositoryException('The original comment is missing.');
    }

    final updated = post.withComments([...post.comments, comment]);
    _replace(_posts, updated, updated.id, (item) => item.id);
  }

  @override
  Future<void> toggleSaved(String postId) async {
    await _wait();
    _requirePost(postId);
    _toggle(_saved, postId);
  }

  @override
  Future<void> toggleHelpful(String postId) async {
    await _wait();
    _requirePost(postId);
    _toggle(_helpful, postId);
  }

  @override
  Future<void> toggleTopic(String topic) async {
    await _wait();

    if (!topics.contains(topic)) {
      throw const RepositoryException('Unknown topic.');
    }

    _toggle(_followed, topic);
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    await _wait();
    _profile = profile;
  }

  @override
  Future<void> reportPost(ContentReport report) async {
    await _wait();
    _requirePost(report.postId);
    _reports.add(report);
  }
}

abstract class ReflectionAssistant {
  Future<String> reflect(String text);
}

// Retained for local tests and explicitly simulated demonstrations.
class DemoReflectionAssistant implements ReflectionAssistant {
  @override
  Future<String> reflect(String text) async {
    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );

    return 'SIMULATED EXAMPLE\n\n'
        'Possible obstacle: getting started feels difficult.\n\n'
        'Small next step: choose a five-minute action.\n\n'
        'Reflection question: what would make starting easier?\n\n'
        'This is fixed sample text. No AI analyzed your reflection.';
  }
}

class AssistantException implements Exception {
  final String message;

  const AssistantException(this.message);

  @override
  String toString() => message;
}
