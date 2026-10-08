import 'dart:async';

import 'package:flutter/material.dart';

import 'api_feed_repository.dart';
import 'public_profile.dart';
import 'public_profile_screen.dart';
import 'repository.dart';

class PeopleSearchScreen extends StatefulWidget {
  final ApiFeedRepository repository;

  const PeopleSearchScreen({super.key, required this.repository});

  @override
  State<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends State<PeopleSearchScreen> {
  final controller = TextEditingController();

  Timer? timer;
  int requestId = 0;

  List<PersonSearchResult> results = [];
  bool loading = false;
  bool searched = false;
  String? error;

  String get query {
    final text = controller.text.trim();
    return text.startsWith('@') ? text.substring(1).trim() : text;
  }

  @override
  void dispose() {
    timer?.cancel();
    requestId++;
    controller.dispose();
    super.dispose();
  }

  void searchChanged({bool immediately = false}) {
    timer?.cancel();

    final id = ++requestId;
    final text = query;
    final valid = text.length >= 2 && text.length <= 80;

    setState(() {
      results = [];
      searched = false;
      error = null;
      loading = valid;
    });

    if (!valid) return;

    timer = Timer(
      immediately ? Duration.zero : const Duration(milliseconds: 350),
      () => fetchResults(text, id),
    );
  }

  Future<void> fetchResults(String text, int id) async {
    if (!mounted || id != requestId) return;

    try {
      final users = await widget.repository.searchPeople(text);

      // An older response must not replace results for newer input.
      if (!mounted || id != requestId) return;

      setState(() {
        results = users;
        searched = true;
      });
    } catch (exception) {
      if (!mounted || id != requestId) return;

      setState(() {
        error = exception is RepositoryException
            ? exception.message
            : 'Could not search people. Please try again.';
      });
    } finally {
      if (mounted && id == requestId) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> openProfile(PersonSearchResult person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfileScreen(
          personId: person.id,
          repository: widget.repository,
        ),
      ),
    );

    if (!mounted) return;
    searchChanged(immediately: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find people')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    autocorrect: false,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: 'Search name or username',
                      hintText: 'Start typing…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: () {
                                controller.clear();
                                searchChanged();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    onChanged: (_) => searchChanged(),
                  ),
                ),
                if (loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: buildResults()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildResults() {
    if (query.length < 2) {
      return const Center(
        child: Text('Type at least 2 characters to find Anchor users.'),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              TextButton(
                onPressed: () => searchChanged(immediately: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (loading) {
      return const Center(child: Text('Finding people…'));
    }

    if (searched && results.isEmpty) {
      return const Center(child: Text('No matching users found.'));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        ...results.map(
          (person) => Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(person.displayName),
              subtitle: Text('@${person.username}'),
              trailing: person.isMe
                  ? const Text('You')
                  : person.isFollowing
                  ? const Text('Following')
                  : const Icon(Icons.chevron_right),
              onTap: () => openProfile(person),
            ),
          ),
        ),
        if (results.length == 20)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Showing the first 20 matches. '
              'Keep typing to narrow the results.',
            ),
          ),
      ],
    );
  }
}
