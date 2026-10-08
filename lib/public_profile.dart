class PublicProfile {
  final String id;
  final String username;
  final String displayName;
  final String bio;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final bool isFollowing;
  final bool isMe;

  const PublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.followerCount,
    required this.followingCount,
    required this.postCount,
    required this.isFollowing,
    required this.isMe,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String) {
        throw const FormatException('Invalid profile text.');
      }
      return value;
    }

    int count(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw const FormatException('Invalid profile count.');
      }
      return value;
    }

    bool flag(String key) {
      final value = json[key];
      if (value is! bool) {
        throw const FormatException('Invalid profile status.');
      }
      return value;
    }

    return PublicProfile(
      id: text('id'),
      username: text('username'),
      displayName: text('displayName'),
      bio: text('bio'),
      followerCount: count('followerCount'),
      followingCount: count('followingCount'),
      postCount: count('postCount'),
      isFollowing: flag('isFollowing'),
      isMe: flag('isMe'),
    );
  }
}

class PersonSearchResult {
  final String id;
  final String username;
  final String displayName;
  final bool isFollowing;
  final bool isMe;

  const PersonSearchResult({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isFollowing,
    required this.isMe,
  });

  factory PersonSearchResult.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String ||
        json['username'] is! String ||
        json['displayName'] is! String ||
        json['isFollowing'] is! bool ||
        json['isMe'] is! bool) {
      throw const FormatException('Invalid search result.');
    }

    return PersonSearchResult(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      isFollowing: json['isFollowing'] as bool,
      isMe: json['isMe'] as bool,
    );
  }
}
