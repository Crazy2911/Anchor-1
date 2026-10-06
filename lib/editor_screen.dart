import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'repository.dart';
import 'app_state.dart';
import 'models.dart';
import 'widgets.dart';

enum EditorKind { goal, habit, reflection, post, profile }

class EditorArgs {
  final EditorKind kind;
  final String? id;

  const EditorArgs({required this.kind, this.id});
}

class EditorScreen extends StatefulWidget {
  final EditorArgs args;

  const EditorScreen({super.key, required this.args});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  final regionController = TextEditingController();

  String? selectedGoal;
  String selectedTopic = '';
  int topicFieldVersion = 0;
  String mood = 'Okay';

  bool initialized = false;
  bool validTarget = true;
  bool publicConfirmed = false;
  bool aiLoading = false;
  bool planning = false;
  bool improvingPost = false;
  String? aiExample;

  Goal? existingGoal;
  Habit? existingHabit;
  Reflection? existingReflection;
  CommunityPost? existingPost;

  EditorKind get kind => widget.args.kind;
  bool get editing => widget.args.id != null;
  String? draftId;
  String? aiError;

  Future<void> suggestPlan() async {
    final state = context.read<AppState>();
    final planner = state.planner;

    if (planning || state.busy) return;

    if (planner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI planning is not connected in this build.'),
        ),
      );
      return;
    }

    final originalTitle = titleController.text;
    final originalBody = bodyController.text;
    final originalGoalId = selectedGoal;

    final isGoal = kind == EditorKind.goal;

    final text = isGoal
        ? '${originalTitle.trim()}\n${originalBody.trim()}'.trim()
        : originalTitle.trim();

    if (isGoal && text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe your goal before asking for help.'),
        ),
      );
      return;
    }

    final data = state.data;

    if (data == null) return;

    final goal = findById(data.goals, originalGoalId, (item) => item.id);

    if (!isGoal && goal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a linked goal first.')),
      );
      return;
    }

    final preview = isGoal
        ? text
        : 'Goal: ${goal!.title}\n\n'
              'Purpose: ${goal.reason}\n\n'
              'Habit description: '
              '${text.isEmpty ? "Suggest a small starting action." : text}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ask AI for a suggestion?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
              'The information shown below will be sent to Groq. '
              'If Groq reaches its usage limit, it will also be sent '
              'to Google Gemini for processing. '
              'Private reflections are not included. '
              'You can review the suggestion before applying it.',
            ),
              const SizedBox(height: 16),
              SelectableText(preview),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Generate suggestion'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => planning = true);

    try {
      final suggestion = await planner.suggest(
        task: isGoal ? 'goal' : 'habit',
        text: text,
        goalId: isGoal ? null : originalGoalId,
      );

      if (!mounted) return;

      // Avoid replacing a newer draft with a suggestion for older input.
      if (titleController.text != originalTitle ||
          (isGoal && bodyController.text != originalBody) ||
          (!isGoal && selectedGoal != originalGoalId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your form changed while AI was working. '
              'Ask again to use the updated information.',
            ),
          ),
        );
        return;
      }

      final apply = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Review AI suggestion'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  suggestion.title,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(suggestion.reason),
                const SizedBox(height: 16),
                const Text(
                  'Applying fills the form. You can edit it before saving.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use suggestion'),
            ),
          ],
        ),
      );

      if (!mounted || apply != true) return;

      setState(() {
        titleController.text = suggestion.title;

        if (isGoal) {
          bodyController.text = suggestion.reason;
        }
      });
    } on AssistantException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI planning is unavailable. Your form is unchanged.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => planning = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;

    final state = context.read<AppState>();
    final data = state.data!;
    final id = widget.args.id;

    switch (kind) {
      case EditorKind.goal:
        existingGoal = findById(data.goals, id, (item) => item.id);
        titleController.text = existingGoal?.title ?? '';
        bodyController.text = existingGoal?.reason ?? '';
        validTarget = !editing || existingGoal != null;
        break;

      case EditorKind.habit:
        existingHabit = findById(data.habits, id, (item) => item.id);
        titleController.text = existingHabit?.title ?? '';
        selectedGoal =
            existingHabit?.goalId ??
            (data.goals.isEmpty ? null : data.goals.first.id);
        validTarget = !editing || existingHabit != null;
        break;

      case EditorKind.reflection:
        existingReflection = findById(data.reflections, id, (item) => item.id);
        titleController.text = existingReflection?.title ?? '';
        bodyController.text = existingReflection?.body ?? '';
        mood = existingReflection?.mood ?? 'Okay';
        validTarget = !editing || existingReflection != null;
        break;

      case EditorKind.post:
        existingPost = findById(data.posts, id, (item) => item.id);
        titleController.text = existingPost?.title ?? '';
        bodyController.text = existingPost?.body ?? '';
        selectedTopic = existingPost?.topic ?? '';
        validTarget =
            !editing ||
            (existingPost != null && existingPost!.authorId == state.userId);
        break;

      case EditorKind.profile:
        titleController.text = data.profile.name;
        bodyController.text = data.profile.bio;
        regionController.text = data.profile.region;
        break;
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    regionController.dispose();
    super.dispose();
  }

  String get screenTitle {
    final prefix = editing ? 'Edit' : 'Create';

    switch (kind) {
      case EditorKind.goal:
        return '$prefix goal';
      case EditorKind.habit:
        return '$prefix habit';
      case EditorKind.reflection:
        return editing ? 'Edit reflection' : 'Private reflection';
      case EditorKind.post:
        return '$prefix community post';
      case EditorKind.profile:
        return 'Edit profile';
    }
  }

  String get titleLabel {
    switch (kind) {
      case EditorKind.goal:
        return 'What is your goal?';
      case EditorKind.habit:
        return 'What action will you practice?';
      case EditorKind.reflection:
        return 'Reflection title';
      case EditorKind.post:
        return 'Post title';
      case EditorKind.profile:
        return 'Display name';
    }
  }

  String get bodyLabel {
    switch (kind) {
      case EditorKind.goal:
        return 'Why does this matter to you?';
      case EditorKind.reflection:
        return 'What happened? What helped or got in the way?';
      case EditorKind.post:
        return 'Describe your obstacle, experience, or useful strategy';
      case EditorKind.profile:
        return 'Bio — optional';
      case EditorKind.habit:
        return '';
    }
  }

  String? validateText(
    String? value, {
    required int minimum,
    required int maximum,
  }) {
    final text = (value ?? '').trim();

    if (text.length < minimum) {
      return 'Enter at least $minimum characters.';
    }

    if (text.length > maximum) {
      return 'Use $maximum characters or fewer.';
    }

    return null;
  }

  Future<void> showAiExample() async {
    if (aiLoading) return;

    final text = bodyController.text.trim();

    if (text.length < 10 || text.length > 3000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Write a reflection between 10 and 3,000 characters first.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ask AI about this reflection?'),
        content: const Text(
          'The current reflection text will be sent to Groq. '
          'If Groq reaches its usage limit, it will also be sent '
          'to Google Gemini for processing. '
          'Remove anything you do not want to share.\n\n'
          'This does not publish your reflection or change your saved entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send for assistance'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    final assistant = context.read<AppState>().assistant;

    setState(() {
      aiLoading = true;
      aiError = null;
      aiExample = null;
    });

    try {
      final result = await assistant.reflect(text);

      if (!mounted) return;

      setState(() {
        aiExample = result;
      });
    } on AssistantException catch (error) {
      if (!mounted) return;

      setState(() {
        aiError = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        aiError =
            'AI assistance is unavailable. '
            'You can continue writing and save your reflection.';
      });
    } finally {
      if (mounted) {
        setState(() {
          aiLoading = false;
        });
      }
    }
  }

  Future<void> improveCommunityPost() async {
    final state = context.read<AppState>();
    final assistant = state.postAssistant;

    if (state.busy || improvingPost) return;

    if (assistant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post assistance is not connected in this build.'),
        ),
      );
      return;
    }

    final originalTitle = titleController.text;
    final originalBody = bodyController.text;
    final originalTopic = selectedTopic;

    if (originalBody.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe your post in at least 10 characters first.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Improve this draft with AI?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
              'Only this draft’s title, body and topic will be sent '
              'to Groq. If Groq reaches its usage limit, the same '
              'information will also be sent to Google Gemini. '
              'Your private reflections are not included. '
              'You can review the suggestion before applying it.',
            ),
              const SizedBox(height: 16),
              Text('Topic: $originalTopic'),
              const SizedBox(height: 8),
              SelectableText(
                '${originalTitle.trim()}\n\n${originalBody.trim()}',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Generate suggestion'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => improvingPost = true);

    try {
      final suggestion = await assistant.improve(
        title: originalTitle.trim(),
        body: originalBody.trim(),
        topic: originalTopic,
      );

      if (!mounted) return;

      if (titleController.text != originalTitle ||
          bodyController.text != originalBody ||
          selectedTopic != originalTopic) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your draft changed while AI was working. '
              'Ask again to use the updated draft.',
            ),
          ),
        );
        return;
      }

      final apply = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Review the suggested post'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('Topic: ${suggestion.topic}'),
                const SizedBox(height: 12),
                SelectableText(suggestion.body),
                const SizedBox(height: 16),
                const Text(
                  'Check that this still represents your experience. '
                  'Applying changes the draft only—it does not publish it.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use suggestion'),
            ),
          ],
        ),
      );

      if (!mounted || apply != true) return;

      setState(() {
        titleController.text = suggestion.title;
        bodyController.text = suggestion.body;
        selectedTopic = suggestion.topic;
        topicFieldVersion++;

        // Ask the user to confirm sharing the revised text.
        publicConfirmed = false;
      });
    } on AssistantException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI assistance failed. Your draft is unchanged.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => improvingPost = false);
      }
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;

    if (kind == EditorKind.post && !publicConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirm that this text is intended for the community.',
          ),
        ),
      );
      return;
    }

    final state = context.read<AppState>();
    final id = widget.args.id ?? (draftId ??= newId());
    final title = titleController.text.trim();
    final body = bodyController.text.trim();

    bool success;

    switch (kind) {
      case EditorKind.goal:
        success = await state.run(
          (repository) =>
              repository.saveGoal(Goal(id: id, title: title, reason: body)),
        );
        break;

      case EditorKind.habit:
        success = await state.run(
          (repository) => repository.saveHabit(
            Habit(
              id: id,
              goalId: selectedGoal!,
              title: title,
              completedOn: existingHabit?.completedOn,
            ),
          ),
        );
        break;

      case EditorKind.reflection:
        success = await state.run(
          (repository) => repository.saveReflection(
            Reflection(id: id, title: title, body: body, mood: mood),
          ),
        );
        break;

      case EditorKind.post:
        success = await state.run(
          (repository) => repository.savePost(
            CommunityPost(
              id: id,
              authorId: state.userId,
              author: state.data!.profile.name,
              title: title,
              body: body,
              topic: selectedTopic.trim(),
              comments: existingPost?.comments ?? [],
            ),
          ),
        );
        break;

      case EditorKind.profile:
        success = await state.run(
          (repository) => repository.saveProfile(
            UserProfile(
              name: title,
              bio: body,
              region: regionController.text.trim(),
            ),
          ),
        );
        break;
    }

    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final data = state.data!;

    if (!validTarget) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unavailable')),
        body: const Center(
          child: Text('This item is missing or cannot be edited.'),
        ),
      );
    }

    if (kind == EditorKind.habit && data.goals.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create habit')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Create a goal first so your habit has a purpose.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context,
                      '/edit',
                      arguments: const EditorArgs(kind: EditorKind.goal),
                    );
                  },
                  child: const Text('Create a goal'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(screenTitle)),
      body: Column(
        children: [
          const ErrorNotice(),
          if (state.saving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: PageBody(
              children: [
                Form(
                  key: formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (kind == EditorKind.reflection) ...[
                        const SurfaceCard(
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Private reflection. This text is not '
                                  'published to the community.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextFormField(
                        controller: titleController,
                        maxLength: kind == EditorKind.profile ? 40 : 100,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(labelText: titleLabel),
                        validator: (value) => validateText(
                          value,
                          minimum: kind == EditorKind.profile ? 2 : 3,
                          maximum: kind == EditorKind.profile ? 40 : 100,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (kind == EditorKind.habit) ...[
                        DropdownButtonFormField<String>(
                          initialValue: selectedGoal,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Linked goal',
                          ),
                          items: data.goals
                              .map(
                                (goal) => DropdownMenuItem(
                                  value: goal.id,
                                  child: Text(
                                    goal.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedGoal = value);
                          },
                          validator: (value) {
                            if (value == null ||
                                !data.goals.any((goal) => goal.id == value)) {
                              return 'Choose an existing goal.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (kind == EditorKind.post) ...[
                        TextFormField(
                        key: ValueKey(topicFieldVersion),
                        initialValue: selectedTopic,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Topic',
                          hintText: 'For example: Gardening or Learning guitar',
                          helperText: 'Enter a topic that describes your post.',
                        ),
                        onChanged: (value) {
                          selectedTopic = value;
                        },
                        validator: (value) => validateText(
                          value,
                          minimum: 1,
                          maximum: 80,
                        ),
                      ),
                        const SizedBox(height: 16),
                      ],
                      if (kind == EditorKind.reflection) ...[
                        DropdownButtonFormField<String>(
                          initialValue: mood,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'How are you feeling?',
                          ),
                          items:
                              [
                                    'Great',
                                    'Good',
                                    'Okay',
                                    'Low',
                                    'Prefer not to say',
                                  ]
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => mood = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (kind != EditorKind.habit)
                        TextFormField(
                          controller: bodyController,
                          minLines: 4,
                          maxLines: 10,
                          maxLength: kind == EditorKind.profile ? 300 : 3000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(labelText: bodyLabel),
                          validator: (value) => validateText(
                            value,
                            minimum: kind == EditorKind.profile ? 0 : 10,
                            maximum: kind == EditorKind.profile ? 300 : 3000,
                          ),
                        ),
                      if (kind == EditorKind.profile) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: regionController,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: 'Country or region — optional',
                            helperText: 'No precise location is needed.',
                          ),
                          validator: (value) =>
                              validateText(value, minimum: 0, maximum: 60),
                        ),
                      ],
                      if (kind == EditorKind.reflection) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: aiLoading ? null : showAiExample,
                          icon: aiLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Help me reflect'),
                        ),
                        if (aiError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            aiError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        if (aiExample != null) ...[
                          const SizedBox(height: 12),
                          SurfaceCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'AI SUGGESTION — REVIEW BEFORE USING',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(aiExample!),
                                TextButton(
                                  onPressed: () {
                                    setState(() => aiExample = null);
                                  },
                                  child: const Text('Dismiss'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                      if (kind == EditorKind.post) ...[
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: publicConfirmed,
                          title: const Text(
                            'I intend to share this text with the community.',
                          ),
                          subtitle: const Text(
                            'Check that it does not include private information.',
                          ),
                          onChanged: (value) {
                            setState(() => publicConfirmed = value ?? false);
                          },
                        ),
                      ],
                      if (kind == EditorKind.goal ||
                          kind == EditorKind.habit) ...[
                        OutlinedButton.icon(
                          onPressed: state.busy || planning || improvingPost
                              ? null
                              : suggestPlan,
                          icon: planning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(
                            planning
                                ? 'Thinking…'
                                : kind == EditorKind.goal
                                ? 'Help me shape this goal'
                                : 'Suggest a manageable habit',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 24),

                      if (kind == EditorKind.post) ...[
                        OutlinedButton.icon(
                          onPressed: state.busy || improvingPost
                              ? null
                              : improveCommunityPost,
                          icon: improvingPost
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_outlined),
                          label: Text(
                            improvingPost
                                ? 'Improving draft…'
                                : 'Improve my post',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: state.busy || planning || improvingPost
                              ? null
                              : save,
                          icon: const Icon(Icons.check),
                          label: Text(
                            state.saving
                                ? 'Saving…'
                                : kind == EditorKind.post
                                ? 'Publish to community'
                                : 'Save',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: state.saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
