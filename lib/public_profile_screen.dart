import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api_feed_repository.dart';
import 'app_state.dart';
import 'public_profile.dart';
import 'repository.dart';

class PublicProfileScreen extends StatefulWidget {
  final String personId;
  final ApiFeedRepository repository;

  const PublicProfileScreen({
    super.key,
    required this.personId,
    required this.repository,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  PublicProfile? profile;
  bool busy = false;
  bool needsRefresh = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  String message(Object exception) {
    if (exception is RepositoryException) return exception.message;
    return 'Could not load this profile. Please try again.';
  }

  Future<void> loadProfile() async {
    if (busy) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final result = await widget.repository.getPublicProfile(widget.personId);

      if (!mounted) return;

      setState(() {
        profile = result;
        needsRefresh = false;
      });
    } catch (exception) {
      if (!mounted) return;

      setState(() {
        error = message(exception);
        needsRefresh = true;
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> toggleFollow() async {
    final current = profile;

    if (busy || needsRefresh || current == null || current.isMe) {
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      await widget.repository.setFollowing(
        current.id,
        following: !current.isFollowing,
      );

      final updated = await widget.repository.getPublicProfile(current.id);

      if (!mounted) return;

      setState(() {
        profile = updated;
        needsRefresh = false;
      });
    } catch (exception) {
      if (!mounted) return;

      setState(() {
        // A timed-out write might have succeeded.
        // Reload before allowing another follow/unfollow action.
        needsRefresh = true;
        error = '${message(exception)} Refresh to check the current status.';
      });
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget stat(String label, int count) {
    return SizedBox(
      width: 100,
      child: Column(
        children: [
          Text('$count', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = profile;
    final data = context.watch<AppState>().data;

    final posts = data?.posts
        .where((post) => post.authorId == widget.personId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: busy ? null : loadProfile,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : loadProfile,
                    child: const Text('Retry / refresh'),
                  ),
                ],
                if (current != null) ...[
                  const SizedBox(height: 20),
                  const Center(
                    child: CircleAvatar(
                      radius: 36,
                      child: Icon(Icons.person_outline, size: 40),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    current.displayName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('@${current.username}', textAlign: TextAlign.center),
                  if (current.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(current.bio, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 16,
                    children: [
                      stat('Posts', current.postCount),
                      stat('Followers', current.followerCount),
                      stat('Following', current.followingCount),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (current.isMe)
                    const Center(child: Text('This is your public profile.'))
                  else
                    Center(
                      child: FilledButton.icon(
                        onPressed: busy || needsRefresh ? null : toggleFollow,
                        icon: Icon(
                          current.isFollowing
                              ? Icons.person_remove_outlined
                              : Icons.person_add_outlined,
                        ),
                        label: Text(
                          current.isFollowing ? 'Unfollow' : 'Follow',
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  Text(
                    'Community posts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (posts == null)
                    const Text('Community posts are not loaded yet.')
                  else if (posts.isEmpty)
                    const Text('No posts in the currently loaded feed.')
                  else
                    ...posts.map(
                      (post) => Card(
                        child: ListTile(
                          title: Text(post.title),
                          subtitle: Text(
                            post.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/post',
                              arguments: post.id,
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
