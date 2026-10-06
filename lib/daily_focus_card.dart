import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'focus_assistant.dart';
import 'models.dart';
import 'repository.dart';
import 'widgets.dart';

class DailyFocusCard extends StatefulWidget {
  const DailyFocusCard({super.key});

  @override
  State<DailyFocusCard> createState() => _DailyFocusCardState();
}

class _DailyFocusCardState extends State<DailyFocusCard> {
  bool thinking = false;
  String? error;
  FocusSuggestion? suggestion;

  Future<void> ask() async {
    final state = context.read<AppState>();
    final assistant = state.focusAssistant;

    if (thinking || state.busy) return;

    if (assistant == null) {
      setState(() => error = 'Dashboard AI is not connected.');
      return;
    }

    final habits = state.data!.habits
        .where((habit) => !habit.completedToday)
        .take(20)
        .toList();

    if (habits.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose a next action with AI?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'The titles of these ${habits.length} incomplete habits '
                'will be sent through your backend to Groq. '
                'Reflections and goal descriptions are not included.',
              ),
              const SizedBox(height: 12),
              ...habits.map(
                (habit) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• ${habit.title}'),
                ),
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
            child: const Text('Suggest next action'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      thinking = true;
      error = null;
      suggestion = null;
    });

    try {
      final result = await assistant.suggest(
        habits.map((habit) => habit.id).toList(),
      );

      if (!mounted) return;

      final current = findById(
        context.read<AppState>().data!.habits,
        result.habitId,
        (habit) => habit.id,
      );

      if (current == null ||
          current.completedToday ||
          current.title != result.title) {
        setState(() {
          error = 'Your habits changed. Ask again for a current suggestion.';
        });
        return;
      }

      setState(() => suggestion = result);
    } on AssistantException catch (exception) {
      if (mounted) {
        setState(() => error = exception.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'AI is unavailable. You can still choose your next action.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => thinking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final habits = state.data!.habits;

    final hasIncomplete = habits.any(
      (habit) => !habit.completedToday,
    );

    final result = suggestion;

    final current = result == null
        ? null
        : findById(
            habits,
            result.habitId,
            (habit) => habit.id,
          );

    final stillRelevant = result != null &&
        current != null &&
        !current.completedToday &&
        current.title == result.title;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_outlined),
          const SizedBox(height: 12),
          Text(
            'What should I do next?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            habits.isEmpty
                ? 'Add a goal and habit to get started.'
                : !hasIncomplete
                    ? 'All your current habits are checked in today.'
                    : 'Ask AI to suggest one of your incomplete habits. '
                        'You remain in control.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: !hasIncomplete || thinking || state.busy
                ? null
                : ask,
            child: Text(
              thinking ? 'Thinking…' : 'Suggest my next action',
            ),
          ),
          if (thinking)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (stillRelevant) ...[
            const SizedBox(height: 16),
            Text(
              result.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(result.reason),
            const SizedBox(height: 8),
            const Text(
              'When you finish, check it off in your daily actions below.',
            ),
            TextButton(
              onPressed: () => setState(() => suggestion = null),
              child: const Text('Dismiss'),
            ),
          ],
        ],
      ),
    );
  }
}