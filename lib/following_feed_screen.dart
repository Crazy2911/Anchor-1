import 'package:flutter/material.dart';

import 'api_feed_repository.dart';
import 'models.dart';
import 'repository.dart';
import 'screens.dart' show PostCard;

class FollowingFeedScreen extends StatefulWidget {
  final ApiFeedRepository repository;

  const FollowingFeedScreen({super.key, required this.repository});

  @override
  State<FollowingFeedScreen> createState() => _FollowingFeedScreenState();
}

class _FollowingFeedScreenState extends State<FollowingFeedScreen> {
  final List<CommunityPost> _posts = [];

  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final requestedOffset = reset ? 0 : _offset;

    try {
      final page = await widget.repository.getFollowingFeed(
        offset: requestedOffset,
      );

      if (!mounted) return;

      setState(() {
        if (reset) _posts.clear();

        final existingIds = _posts.map((post) => post.id).toSet();

        for (final post in page.posts) {
          if (existingIds.add(post.id)) {
            _posts.add(post);
          }
        }

        _offset = requestedOffset + page.posts.length;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is RepositoryException
            ? error.message
            : 'Could not load your feed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Following'),
        actions: [
          IconButton(
            tooltip: 'Refresh feed',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (_posts.isEmpty && !_loading && _error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.people_outline, size: 48),
                      SizedBox(height: 16),
                      Text(
                        'No posts from people you follow yet.',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Search for people in Community and follow '
                        'them to see their posts here.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              ..._posts.map(
                (post) => Padding(
                  key: ValueKey(post.id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PostCard(post: post),
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _loading ? null : () => _load(reset: true),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),

              if (!_loading && _error == null && _hasMore && _posts.isNotEmpty)
                OutlinedButton(
                  onPressed: () => _load(),
                  child: const Text('Load more posts'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
