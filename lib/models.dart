const topics = [
  'Study routines',
  'Creative practice',
  'Digital habits',
  'Everyday wellbeing',
];

const currentUserId = 'me';

class Goal {
  final String id;
  final String title;
  final String reason;

  const Goal({required this.id, required this.title, required this.reason});
}

class Habit {
  final String id;
  final String goalId;
  final String title;
  final String? completedOn;

  const Habit({
    required this.id,
    required this.goalId,
    required this.title,
    this.completedOn,
  });

  bool get completedToday => completedOn == dayKey(DateTime.now());

  Habit toggleToday() {
    return Habit(
      id: id,
      goalId: goalId,
      title: title,
      completedOn: completedToday ? null : dayKey(DateTime.now()),
    );
  }
}

class Reflection {
  final String id;
  final String title;
  final String body;
  final String mood;

  const Reflection({
    required this.id,
    required this.title,
    required this.body,
    required this.mood,
  });
}

class CommunityComment {
  final String id;
  final String authorId;
  final String author;
  final String body;
  final String? parentId;

  const CommunityComment({
    required this.id,
    required this.authorId,
    required this.author,
    required this.body,
    this.parentId,
  });
}

class CommunityPost {
  final String id;
  final String authorId;
  final String author;
  final String title;
  final String body;
  final String topic;
  final List<CommunityComment> comments;

  CommunityPost({
    required this.id,
    required this.authorId,
    required this.author,
    required this.title,
    required this.body,
    required this.topic,
    List<CommunityComment> comments = const [],
  }) : comments = List.unmodifiable(comments);

  CommunityPost withComments(List<CommunityComment> value) {
    return CommunityPost(
      id: id,
      authorId: authorId,
      author: author,
      title: title,
      body: body,
      topic: topic,
      comments: value,
    );
  }
}

class UserProfile {
  final String name;
  final String bio;
  final String region;

  const UserProfile({
    required this.name,
    required this.bio,
    required this.region,
  });
}

class ContentReport {
  final String postId;
  final String reason;

  const ContentReport({required this.postId, required this.reason});
}

// An immutable snapshot for the presentation layer.
class AppData {
  final List<Goal> goals;
  final List<Habit> habits;
  final List<Reflection> reflections;
  final List<CommunityPost> posts;
  final Set<String> savedPostIds;
  final Set<String> helpfulPostIds;
  final Set<String> followedTopics;
  final UserProfile profile;

  AppData({
    required List<Goal> goals,
    required List<Habit> habits,
    required List<Reflection> reflections,
    required List<CommunityPost> posts,
    required Set<String> savedPostIds,
    required Set<String> helpfulPostIds,
    required Set<String> followedTopics,
    required this.profile,
  }) : goals = List.unmodifiable(goals),
       habits = List.unmodifiable(habits),
       reflections = List.unmodifiable(reflections),
       posts = List.unmodifiable(posts),
       savedPostIds = Set.unmodifiable(savedPostIds),
       helpfulPostIds = Set.unmodifiable(helpfulPostIds),
       followedTopics = Set.unmodifiable(followedTopics);
}

String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String newId() => DateTime.now().microsecondsSinceEpoch.toString();

T? findById<T>(Iterable<T> items, String? id, String Function(T) getId) {
  for (final item in items) {
    if (getId(item) == id) return item;
  }
  return null;
}
