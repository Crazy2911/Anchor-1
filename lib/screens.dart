import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'app_state.dart';
import 'editor_screen.dart';
import 'models.dart';
import 'repository.dart';
import 'widgets.dart';
import 'discussion_assistant.dart';
import 'daily_focus_card.dart';
import 'community_post_image.dart';
import 'api_feed_repository.dart';
import 'quote_dialog.dart';
import 'public_profile_screen.dart';
import 'people_search_screen.dart';

void openPublicProfile(BuildContext context, String personId) {
  final repository = context.read<AppState>().repository;

  if (repository is! ApiFeedRepository) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Public profiles require the connected backend.'),
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PublicProfileScreen(personId: personId, repository: repository),
    ),
  );
}

void openEditor(BuildContext context, EditorKind kind, {String? id}) {
  Navigator.pushNamed(
    context,
    '/edit',
    arguments: EditorArgs(kind: kind, id: id),
  );
}

// -----------------------------------------------------------------------------
// HOME: RESPONSIVE NAVIGATION
// -----------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;

  static const labels = ['Today', 'Goals', 'Reflect', 'Community', 'Profile'];

  static const icons = [
    Icons.wb_sunny_outlined,
    Icons.flag_outlined,
    Icons.edit_note_outlined,
    Icons.people_outline,
    Icons.person_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Anchor')),
        body: Center(
          child: state.loading
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.error ?? 'Unable to load Anchor.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: state.load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.anchor_rounded),
                SizedBox(width: 8),
                Text('Anchor'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Saved posts',
                onPressed: () {
                  Navigator.pushNamed(context, '/saved');
                },
                icon: const Icon(Icons.bookmark_outline),
              ),
              IconButton(
                tooltip: state.isDark ? 'Light theme' : 'Dark theme',
                onPressed: state.toggleTheme,
                icon: Icon(
                  state.isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                const ErrorNotice(),
                if (state.busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Row(
                    children: [
                      if (wide)
                        NavigationRail(
                          selectedIndex: selected,
                          labelType: NavigationRailLabelType.all,
                          onDestinationSelected: (value) {
                            setState(() => selected = value);
                          },
                          destinations: List.generate(
                            labels.length,
                            (index) => NavigationRailDestination(
                              icon: Icon(icons[index]),
                              label: Text(labels[index]),
                            ),
                          ),
                        ),
                      Expanded(
                        child: IndexedStack(
                          index: selected,
                          children: const [
                            TodayPage(),
                            GoalsPage(),
                            ReflectionsPage(),
                            CommunityPage(),
                            ProfilePage(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (value) {
                    setState(() => selected = value);
                  },
                  destinations: List.generate(
                    labels.length,
                    (index) => NavigationDestination(
                      icon: Icon(icons[index]),
                      label: labels[index],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// TODAY
// -----------------------------------------------------------------------------

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  Future<void> showMotivation(BuildContext context) async {
    final state = context.read<AppState>();

    if (state.busy || state.data == null) return;

    final repository = state.repository;

    if (repository is! ApiFeedRepository) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Personalized motivation requires the backend.'),
        ),
      );
      return;
    }

    final goals = state.data!.goals;

    if (goals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a goal first to get relevant encouragement.'),
        ),
      );
      return;
    }

    // Choose which goal the encouragement should focus on.
    final String? goalId;

    if (goals.length == 1) {
      goalId = goals.first.id;
    } else {
      goalId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Which goal needs encouragement?'),
          children: goals.map((goal) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, goal.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(goal.title),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (!context.mounted || goalId == null) return;

    // Read fresh data after the goal-selection dialog closes.
    final current = state.data;
    if (current == null) return;

    final goal = findById(current.goals, goalId, (item) => item.id);

    if (goal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That goal is no longer available.')),
      );
      return;
    }

    final habits = current.habits
        .where((habit) => habit.goalId == goal.id)
        .toList();

    final completed = habits.where((habit) => habit.completedToday).length;

    String shorten(String value, int maximum) {
      final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (text.length <= maximum) return text;

      return '${text.substring(0, maximum - 1)}…';
    }

    // Limit the context to fit the endpoint's 2,000-character limit.
    final contextText = StringBuffer()
      ..writeln('My goal: ${shorten(goal.title, 100)}')
      ..writeln('Why it matters: ${shorten(goal.reason, 300)}')
      ..writeln()
      ..writeln(
        'Today: $completed of ${habits.length} linked habits '
        'are checked in.',
      );

    if (habits.isEmpty) {
      contextText.writeln('No habits are linked to this goal yet.');
    } else {
      contextText.writeln('Linked habits (up to 8 shown):');

      for (final habit in habits.take(8)) {
        final status = habit.completedToday
            ? 'checked in today'
            : 'not checked in today';

        contextText.writeln('- ${shorten(habit.title, 100)}: $status');
      }

      if (habits.length > 8) {
        contextText.writeln(
          '${habits.length - 8} additional habits are not listed.',
        );
      }
    }

    await showDialog<void>(
      context: context,
      builder: (_) => QuoteDialog(
        initialText: contextText.toString().trim(),
        generate: (text, tone) =>
            repository.generateQuote(text: text, tone: tone),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;

    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final completed = data.habits.where((habit) => habit.completedToday).length;

    final colors = Theme.of(context).colorScheme;

    return PageBody(
      children: [
        SectionTitle(
          title: 'Hello, ${data.profile.name}',
          subtitle: 'A small step today is a good place to start.',
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TODAY’S ANCHOR',
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Progress, at your pace.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$completed of ${data.habits.length} habits checked in today',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              AnimatedProgress(
                value: data.habits.isEmpty ? 0 : completed / data.habits.length,
                label: 'Today’s completed habits',
                semanticValue: '$completed of ${data.habits.length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Personal motivation, separate from community posts.
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_outline, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                'A little encouragement',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Get encouragement based on your goal, its linked habits, '
                'and today’s check-ins.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Nothing is posted to the community. '
                'You choose what to share with AI.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.busy ? null : () => showMotivation(context),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Find encouragement'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const DailyFocusCard(),
        const SizedBox(height: 16),
        SectionTitle(
          title: 'Your daily actions',
          subtitle: 'Check in when you complete an action.',
          action: FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => openEditor(context, EditorKind.habit),
            icon: const Icon(Icons.add),
            label: const Text('Add habit'),
          ),
        ),
        if (data.habits.isEmpty)
          const EmptyMessage('Create a goal, then add your first habit.'),
        ...data.habits.map(
          (habit) => HabitTile(key: ValueKey(habit.id), habit: habit),
        ),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(height: 12),
              Text(
                'A moment for yourself',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('What helped you move forward today?'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => openEditor(context, EditorKind.reflection),
                child: const Text('Write privately'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// HABIT CARD
// -----------------------------------------------------------------------------

class HabitTile extends StatelessWidget {
  final Habit habit;

  const HabitTile({super.key, required this.habit});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final goal = findById(state.data!.goals, habit.goalId, (item) => item.id);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(habit.title),
            subtitle: Text(goal?.title ?? 'Goal unavailable'),
            value: habit.completedToday,
            onChanged: state.busy
                ? null
                : (_) async {
                    await state.run(
                      (repository) => repository.saveHabit(habit.toggleToday()),
                    );
                  },
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => openEditor(context, EditorKind.habit, id: habit.id),
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        final confirmed = await confirmDelete(
                          context,
                          'This removes the habit and its current check-in.',
                        );

                        if (!confirmed || !context.mounted) return;

                        await state.run(
                          (repository) => repository.deleteHabit(habit.id),
                        );
                      },
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// GOALS
// -----------------------------------------------------------------------------

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data!;

    return PageBody(
      children: [
        SectionTitle(
          title: 'Goals with a purpose',
          subtitle: 'Connect your daily actions to something that matters.',
          action: FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => openEditor(context, EditorKind.goal),
            icon: const Icon(Icons.add),
            label: const Text('Create goal'),
          ),
        ),
        if (data.goals.isEmpty)
          const EmptyMessage('Your first goal can start small.'),
        ...data.goals.map((goal) {
          // These variables belong to this individual goal.
          final habits = data.habits
              .where((habit) => habit.goalId == goal.id)
              .toList();

          final done = habits.where((habit) => habit.completedToday).length;

          return SurfaceCard(
            key: ValueKey(goal.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(goal.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(goal.reason),
                const SizedBox(height: 16),
                Text('$done of ${habits.length} linked habits done today'),
                const SizedBox(height: 10),
                AnimatedProgress(
                  value: habits.isEmpty ? 0 : done / habits.length,
                  label: '${goal.title}: today’s habits',
                  semanticValue: '$done of ${habits.length}',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => openEditor(
                              context,
                              EditorKind.goal,
                              id: goal.id,
                            ),
                      child: const Text('Edit goal'),
                    ),
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () async {
                              final confirmed = await confirmDelete(
                                context,
                                'This also removes habits linked to this goal.',
                              );

                              if (!confirmed || !context.mounted) return;

                              await state.run(
                                (repository) => repository.deleteGoal(goal.id),
                              );
                            },
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// PRIVATE REFLECTIONS
// -----------------------------------------------------------------------------

class ReflectionsPage extends StatelessWidget {
  const ReflectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return PageBody(
      children: [
        SectionTitle(
          title: 'Your private space',
          subtitle: 'Reflections are separate from community posts.',
          action: FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => openEditor(context, EditorKind.reflection),
            icon: const Icon(Icons.add),
            label: const Text('Write reflection'),
          ),
        ),
        if (state.data!.reflections.isEmpty)
          const EmptyMessage('What would you like to remember about today?'),
        ...state.data!.reflections.map(
          (reflection) => SurfaceCard(
            key: ValueKey(reflection.id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reflection.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Chip(label: Text(reflection.mood)),
                const SizedBox(height: 8),
                Text(reflection.body),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () => openEditor(
                              context,
                              EditorKind.reflection,
                              id: reflection.id,
                            ),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () async {
                              final confirmed = await confirmDelete(
                                context,
                                'This removes the reflection.',
                              );

                              if (!confirmed || !context.mounted) return;

                              await state.run(
                                (repository) =>
                                    repository.deleteReflection(reflection.id),
                              );
                            },
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// COMMUNITY FEED
// -----------------------------------------------------------------------------

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  String query = '';
  String? selectedTopic;
  bool followingOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;

    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final availableTopics =
        <String>{
          for (final post in data.posts)
            if (post.topic.trim().isNotEmpty) post.topic,
          for (final followedTopic in data.followedTopics)
            if (followedTopic.trim().isNotEmpty) followedTopic,
        }.toList()..sort((a, b) {
          final comparison = a.toLowerCase().compareTo(b.toLowerCase());
          return comparison == 0 ? a.compareTo(b) : comparison;
        });

    // Fall back to all topics if the selected topic no longer exists.
    final activeTopic = availableTopics.contains(selectedTopic)
        ? selectedTopic
        : null;

    final search = query.trim().toLowerCase();

    final posts = data.posts.where((post) {
      final matchesText = '${post.title} ${post.body} ${post.topic}'
          .toLowerCase()
          .contains(search);

      final matchesTopic = activeTopic == null || activeTopic == post.topic;

      final matchesFollowing =
          !followingOnly || data.followedTopics.contains(post.topic);

      return matchesText && matchesTopic && matchesFollowing;
    }).toList();

    final isFollowing =
        activeTopic != null && data.followedTopics.contains(activeTopic);

    return PageBody(
      children: [
        SectionTitle(
          title: 'Learn together',
          subtitle:
              'Share an obstacle, contribute an idea, report what helped.',
          action: FilledButton.icon(
            onPressed: state.busy
                ? null
                : () => openEditor(context, EditorKind.post),
            icon: const Icon(Icons.add),
            label: const Text('Create post'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: state.busy
                ? null
                : () {
                    final repository = state.repository;

                    if (repository is! ApiFeedRepository) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('People search requires the backend.'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PeopleSearchScreen(repository: repository),
                      ),
                    );
                  },
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Find people'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search community',
            hintText: 'Search posts or topics',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() => query = value);
          },
        ),
        const SizedBox(height: 12),

        // Scroll horizontally so many topics don't fill the page.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('All topics'),
                  selected: activeTopic == null,
                  onSelected: (_) {
                    setState(() => selectedTopic = null);
                  },
                ),
              ),
              ...availableTopics.map(
                (value) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(value),
                    selected: activeTopic == value,
                    onSelected: (_) {
                      setState(() => selectedTopic = value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Followed topics only'),
          value: followingOnly,
          onChanged: (value) {
            setState(() => followingOnly = value);
          },
        ),
        if (activeTopic != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : () async {
                      final topicToToggle = activeTopic;

                      final success = await state.run(
                        (repository) => repository.toggleTopic(topicToToggle),
                      );

                      if (!context.mounted || success) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            state.error ??
                                'Could not update your followed topics.',
                          ),
                        ),
                      );
                    },
              icon: Icon(isFollowing ? Icons.check : Icons.add),
              label: Text(
                isFollowing ? 'Unfollow $activeTopic' : 'Follow $activeTopic',
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: state.busy ? null : state.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh community'),
          ),
        ),
        const SizedBox(height: 12),
        if (posts.isEmpty)
          const EmptyMessage('No matching posts. Try another search or topic.'),
        ...posts.map(
          (post) => EntryReveal(
            key: ValueKey(post.id),
            child: PostCard(post: post),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// COMMUNITY POST CARD
// -----------------------------------------------------------------------------

class PostCard extends StatelessWidget {
  final CommunityPost post;

  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final saved = state.data!.savedPostIds.contains(post.id);

    final author = post.authorId == state.userId
        ? state.data!.profile.name
        : post.author;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Chip(label: Text(post.topic)),
          const SizedBox(height: 8),
          Text(post.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(post.body, maxLines: 3, overflow: TextOverflow.ellipsis),
          CommunityPostImage(post: post),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => openPublicProfile(context, post.authorId),
                child: Text(author),
              ),
              Text(
                '${post.comments.length} comments',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/post', arguments: post.id);
                },
                child: const Text('Open discussion'),
              ),
              IconButton(
                tooltip: saved ? 'Remove bookmark' : 'Save post',
                onPressed: state.busy
                    ? null
                    : () async {
                        await state.run(
                          (repository) => repository.toggleSaved(post.id),
                        );
                      },
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// POST DETAILS, COMMENTS AND REPLIES
// -----------------------------------------------------------------------------

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final formKey = GlobalKey<FormState>();
  final commentController = TextEditingController();

  String? replyTo;
  String? replyAuthor;

  bool summarizing = false;
  Future<void> summarizeDiscussion() async {
    final state = context.read<AppState>();
    final assistant = state.discussionAssistant;

    if (summarizing || state.busy) return;

    if (assistant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Discussion AI is not connected in this build.'),
        ),
      );
      return;
    }

    final post = findById(state.data!.posts, widget.postId, (item) => item.id);

    if (post == null) return;

    if (post.comments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a contribution before summarizing.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Summarize this discussion?'),
        content: const Text(
          'This public post and up to its first 20 comments will be sent '
          'through your backend to Groq. Private reflections are not included.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Summarize'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => summarizing = true);

    try {
      final result = await assistant.summarize(widget.postId);

      if (!mounted) return;

      Widget section(String title, List<SummaryItem> items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('None identified in the included comments.'),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.text),
                    ...item.commentIds.map((id) {
                      final source = findById(
                        post.comments,
                        id,
                        (comment) => comment.id,
                      );

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          source == null
                              ? 'Source comment is not in this local snapshot. '
                                    'Refresh the discussion to inspect it.'
                              : 'Source comment:\n“${source.body}”',
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('AI discussion summary'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Based on ${result.includedCount} of '
                  '${result.totalCount} comments.',
                ),
                const SizedBox(height: 12),
                Text(result.summary),
                section('Suggestions discussed', result.suggestions),
                section('Reported experiences', result.outcomes),
                const SizedBox(height: 12),
                const Text(
                  'Check the source comments. '
                  'AI summaries can misinterpret a discussion.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on AssistantException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The discussion summary is unavailable.')),
      );
    } finally {
      if (mounted) {
        setState(() => summarizing = false);
      }
    }
  }

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  Future<void> sendComment() async {
    if (!formKey.currentState!.validate()) return;

    final state = context.read<AppState>();

    final success = await state.run(
      (repository) => repository.addComment(
        widget.postId,
        CommunityComment(
          id: newId(),
          authorId: state.userId,
          author: state.data!.profile.name,
          body: commentController.text.trim(),
          parentId: replyTo,
        ),
      ),
    );

    if (!success || !mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.error ??
                'The comment could not be confirmed. '
                    'Refresh the discussion before trying again.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }

    // Reset validation before clearing the submitted text.
    formKey.currentState!.reset();
    commentController.clear();

    setState(() {
      replyTo = null;
      replyAuthor = null;
    });
  }

  Future<void> report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Report post'),
        children:
            ['Spam', 'Harassment', 'Personal information', 'Unsafe advice']
                .map(
                  (reason) => SimpleDialogOption(
                    onPressed: () {
                      Navigator.pop(dialogContext, reason);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(reason),
                    ),
                  ),
                )
                .toList(),
      ),
    );

    if (reason == null || !mounted) return;

    final state = context.read<AppState>();

    final success = await state.run(
      (repository) => repository.reportPost(
        ContentReport(postId: widget.postId, reason: reason),
      ),
    );

    if (!success || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Report saved on the server. Moderator review is not available yet.',
        ),
      ),
    );
  }

  Widget commentTile(CommunityComment comment, {bool nested = false}) {
    final state = context.read<AppState>();

    final author = comment.authorId == state.userId
        ? state.data!.profile.name
        : comment.author;

    return Padding(
      key: ValueKey(comment.id),
      padding: EdgeInsets.only(left: nested ? 20 : 0),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(author, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(comment.body),
            if (!nested)
              TextButton(
                onPressed: state.busy
                    ? null
                    : () {
                        setState(() {
                          replyTo = comment.id;
                          replyAuthor = author;
                        });
                      },
                child: const Text('Reply'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;

    if (data == null) return const MissingScreen();

    final post = findById(data.posts, widget.postId, (item) => item.id);

    if (post == null) return const MissingScreen();

    final ownPost = post.authorId == state.userId;
    final helpful = data.helpfulPostIds.contains(post.id);
    final saved = data.savedPostIds.contains(post.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discussion'),
        actions: [
          IconButton(
            tooltip: 'Refresh discussion',
            onPressed: state.busy ? null : state.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: SafeArea(
        child: Column(
          children: [
            const ErrorNotice(),
            if (state.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: PageBody(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text(post.topic)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    post.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => openPublicProfile(context, post.authorId),
                    child: Text(ownPost ? data.profile.name : post.author),
                  ),
                  const SizedBox(height: 20),
                  Text(post.body, style: Theme.of(context).textTheme.bodyLarge),
                  Text(post.body, style: Theme.of(context).textTheme.bodyLarge),
                  CommunityPostImage(post: post),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () async {
                                await state.run(
                                  (repository) =>
                                      repository.toggleHelpful(post.id),
                                );
                              },
                        icon: Icon(
                          helpful ? Icons.thumb_up : Icons.thumb_up_outlined,
                        ),
                        label: Text(helpful ? 'Marked helpful' : 'Helpful'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () async {
                                await state.run(
                                  (repository) =>
                                      repository.toggleSaved(post.id),
                                );
                              },
                        icon: Icon(
                          saved ? Icons.bookmark : Icons.bookmark_outline,
                        ),
                        label: Text(saved ? 'Saved' : 'Save'),
                      ),
                      TextButton(
                        onPressed: state.busy ? null : report,
                        child: const Text('Report'),
                      ),
                      if (ownPost) ...[
                        TextButton(
                          onPressed: state.busy
                              ? null
                              : () => openEditor(
                                  context,
                                  EditorKind.post,
                                  id: post.id,
                                ),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: state.busy
                              ? null
                              : () async {
                                  final confirmed = await confirmDelete(
                                    context,
                                    'This removes the post and its demo discussion.',
                                  );

                                  if (!confirmed || !mounted) return;

                                  final success = await state.run(
                                    (repository) =>
                                        repository.deletePost(post.id),
                                  );

                                  if (!context.mounted) return;

                                  if (success) {
                                    Navigator.pop(context);
                                  }
                                },
                          child: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: state.busy || summarizing
                          ? null
                          : summarizeDiscussion,
                      icon: summarizing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: Text(
                        summarizing ? 'Summarizing…' : 'Summarize discussion',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionTitle(
                    title: 'Contributions',
                    subtitle: 'Ask a question or share what helped you.',
                  ),
                  if (post.comments.isEmpty)
                    const EmptyMessage('Start the discussion.'),
                  ...post.comments
                      .where((comment) => comment.parentId == null)
                      .expand<Widget>(
                        (comment) => [
                          commentTile(comment),
                          ...post.comments
                              .where((reply) => reply.parentId == comment.id)
                              .map((reply) => commentTile(reply, nested: true)),
                        ],
                      ),
                  if (replyTo != null)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Replying to $replyAuthor'),
                        TextButton(
                          onPressed: state.busy
                              ? null
                              : () {
                                  setState(() {
                                    replyTo = null;
                                    replyAuthor = null;
                                  });
                                },
                          child: const Text('Cancel reply'),
                        ),
                      ],
                    ),
                  Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: commentController,
                          enabled: !state.busy,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Your contribution',
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();

                            if (text.length < 3) {
                              return 'Write at least 3 characters.';
                            }

                            if (text.length > 1000) {
                              return 'Use 1,000 characters or fewer.';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: state.busy ? null : sendComment,
                          child: const Text('Post contribution'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SAVED POSTS
// -----------------------------------------------------------------------------

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data;

    if (data == null) return const MissingScreen();

    final posts = data.posts
        .where((post) => data.savedPostIds.contains(post.id))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved posts')),
      body: SafeArea(
        child: Column(
          children: [
            const ErrorNotice(),
            if (state.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: PageBody(
                children: [
                  if (posts.isEmpty)
                    const EmptyMessage(
                      'Save a useful discussion to find it here.',
                    ),
                  ...posts.map(
                    (post) => PostCard(key: ValueKey(post.id), post: post),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PROFILE
// -----------------------------------------------------------------------------

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final auth = context.watch<AuthState>();
    final data = state.data!;

    final ownPosts = data.posts
        .where((post) => post.authorId == state.userId)
        .toList();

    return PageBody(
      children: [
        OutlinedButton.icon(
          onPressed: () => openPublicProfile(context, state.userId),
          icon: const Icon(Icons.public),
          label: const Text('View my public profile'),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 20),

        if (auth.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              auth.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),

        OutlinedButton.icon(
          onPressed: state.busy || auth.busy ? null : auth.signOut,
          icon: const Icon(Icons.logout),
          label: Text(auth.busy ? 'Signing out…' : 'Sign out'),
        ),

        const SizedBox(height: 12),

        const Text(
          'Accounts and community posts are saved on the server. '
          'Goals, habits, reflections, profile edits and bookmarks '
          'are still session-only.',
        ),
        SectionTitle(
          title: data.profile.name,
          subtitle: data.profile.bio.isEmpty
              ? 'Make this space your own.'
              : data.profile.bio,
          action: OutlinedButton(
            onPressed: state.busy
                ? null
                : () => openEditor(context, EditorKind.profile),
            child: const Text('Edit profile'),
          ),
        ),
        if (data.profile.region.isNotEmpty)
          Text('Region: ${data.profile.region}'),
        const SizedBox(height: 20),
        const SectionTitle(
          title: 'Followed topics',
          subtitle: 'Choose the conversations you want to learn from.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topics
              .map(
                (topic) => FilterChip(
                  label: Text(topic),
                  selected: data.followedTopics.contains(topic),
                  onSelected: state.busy
                      ? null
                      : (_) async {
                          await state.run(
                            (repository) => repository.toggleTopic(topic),
                          );
                        },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        const SectionTitle(
          title: 'Your community posts',
          subtitle: 'Your private reflections never appear here.',
        ),
        if (ownPosts.isEmpty)
          const EmptyMessage('You have not published a post yet.'),
        ...ownPosts.map((post) => PostCard(key: ValueKey(post.id), post: post)),
        const SizedBox(height: 16),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Local demonstration',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'No account, backend, database, or live AI is connected. '
                'All changes remain in this app session.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () async {
                        final repository = state.repository;

                        if (repository is MemoryAnchorRepository) {
                          repository.failNextRequest = true;
                          await state.load();
                        }
                      },
                child: const Text('Demonstrate a loading error'),
              ),
              TextButton(
                onPressed: state.busy ? null : state.load,
                child: const Text('Retry loading'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// MISSING SCREEN
// -----------------------------------------------------------------------------

class MissingScreen extends StatelessWidget {
  const MissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This item or screen is no longer available.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
