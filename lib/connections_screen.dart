import 'package:flutter/material.dart';

import 'api_feed_repository.dart';
import 'public_profile.dart';
import 'public_profile_screen.dart';
import 'repository.dart';

class ConnectionsScreen extends StatefulWidget {
  final String personId;
  final bool followers;
  final ApiFeedRepository repository;

  const ConnectionsScreen({
    super.key,
    required this.personId,
    required this.followers,
    required this.repository,
  });

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final List<PersonSearchResult> _users = [];

  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final requestedOffset = reset ? 0 : _offset;

    try {
      final page = await widget.repository.getConnections(
        personId: widget.personId,
        followers: widget.followers,
        offset: requestedOffset,
      );

      if (!mounted) return;

      setState(() {
        if (reset) _users.clear();

        final existingIds = _users.map((person) => person.id).toSet();

        for (final person in page.users) {
          if (existingIds.add(person.id)) {
            _users.add(person);
          }
        }

        _offset = requestedOffset + page.users.length;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is RepositoryException
            ? error.message
            : 'Could not load people. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openPerson(PersonSearchResult person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfileScreen(
          personId: person.id,
          repository: widget.repository,
        ),
      ),
    );

    if (!mounted) return;

    // Refresh labels after following or unfollowing on a profile.
    await _loadPage(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.followers ? 'Followers' : 'Following'),
        actions: [
          IconButton(
            tooltip: 'Refresh people',
            onPressed: _loading ? null : () => _loadPage(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadPage(reset: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_users.isEmpty && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  widget.followers
                      ? 'No followers yet.'
                      : 'Not following anyone yet.',
                  textAlign: TextAlign.center,
                ),
              ),

            ..._users.map(
              (person) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(person.displayName),
                  subtitle: Text('@${person.username}'),
                  trailing: person.isMe
                      ? const Text('You')
                      : person.isFollowing
                      ? const Text('Following')
                      : const Icon(Icons.chevron_right),
                  onTap: _loading ? null : () => _openPerson(person),
                ),
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
                      onPressed: _loading ? null : () => _loadPage(reset: true),
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

            if (!_loading && _error == null && _hasMore && _users.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () => _loadPage(),
                  child: const Text('Load more'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
