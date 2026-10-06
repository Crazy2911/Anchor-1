import 'package:flutter_test/flutter_test.dart';

import 'package:project/app_state.dart';
import 'package:project/models.dart';
import 'package:project/repository.dart';

void main() {
  late MemoryAnchorRepository repository;
  late AppState state;

  setUp(() async {
    repository = MemoryAnchorRepository();

    state = AppState(
      repository: repository,
      assistant: DemoReflectionAssistant(),
    );

    await state.load();
  });

  tearDown(() {
    state.dispose();
  });

  test('creates a goal and a habit linked to that goal', () async {
    final goalSaved = await state.run(
      (repository) => repository.saveGoal(
        const Goal(
          id: 'test-goal',
          title: 'Practice Flutter',
          reason: 'Understand how my application works.',
        ),
      ),
    );

    expect(goalSaved, isTrue);

    final habitSaved = await state.run(
      (repository) => repository.saveHabit(
        const Habit(
          id: 'test-habit',
          goalId: 'test-goal',
          title: 'Practice for 20 minutes',
        ),
      ),
    );

    expect(habitSaved, isTrue);

    final habit = state.data!.habits.singleWhere(
      (habit) => habit.id == 'test-habit',
    );

    expect(habit.goalId, 'test-goal');
    expect(habit.completedToday, isFalse);
  });

  test('rejects a habit whose goal does not exist', () async {
    final success = await state.run(
      (repository) => repository.saveHabit(
        const Habit(
          id: 'invalid-habit',
          goalId: 'missing-goal',
          title: 'Practice something',
        ),
      ),
    );

    expect(success, isFalse);
    expect(state.error, 'Choose an existing goal.');

    expect(
      state.data!.habits.any((habit) => habit.id == 'invalid-habit'),
      isFalse,
    );

    expect(state.busy, isFalse);
  });

  test('checks and unchecks a habit for today', () async {
    final original = state.data!.habits.first;

    final checked = await state.run(
      (repository) => repository.saveHabit(original.toggleToday()),
    );

    expect(checked, isTrue);

    final completed = state.data!.habits.singleWhere(
      (habit) => habit.id == original.id,
    );

    expect(completed.completedToday, isTrue);

    final unchecked = await state.run(
      (repository) => repository.saveHabit(completed.toggleToday()),
    );

    expect(unchecked, isTrue);

    final updated = state.data!.habits.singleWhere(
      (habit) => habit.id == original.id,
    );

    expect(updated.completedToday, isFalse);
  });

  test('a previous day check-in does not count for today', () {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    final habit = Habit(
      id: 'older-habit',
      goalId: 'g1',
      title: 'Read a few pages',
      completedOn: dayKey(yesterday),
    );

    expect(habit.completedToday, isFalse);
  });

  test('deleting a goal removes only its linked habits', () async {
    final original = state.data!;
    final goal = original.goals.first;

    final unrelatedHabitIds = original.habits
        .where((habit) => habit.goalId != goal.id)
        .map((habit) => habit.id)
        .toSet();

    final success = await state.run(
      (repository) => repository.deleteGoal(goal.id),
    );

    expect(success, isTrue);

    expect(state.data!.goals.any((item) => item.id == goal.id), isFalse);

    expect(state.data!.habits.any((habit) => habit.goalId == goal.id), isFalse);

    final remainingHabitIds = state.data!.habits
        .map((habit) => habit.id)
        .toSet();

    expect(remainingHabitIds.containsAll(unrelatedHabitIds), isTrue);
  });

  test('saving a reflection does not publish a community post', () async {
    final originalPostIds = state.data!.posts.map((post) => post.id).toList();

    final success = await state.run(
      (repository) => repository.saveReflection(
        const Reflection(
          id: 'private-reflection',
          title: 'A small step today',
          body: 'I practiced for ten minutes and noticed what helped.',
          mood: 'Good',
        ),
      ),
    );

    expect(success, isTrue);

    expect(
      state.data!.reflections.any(
        (reflection) => reflection.id == 'private-reflection',
      ),
      isTrue,
    );

    expect(
      state.data!.posts.map((post) => post.id).toList(),
      orderedEquals(originalPostIds),
    );
  });

  test('failed write preserves data and can be retried', () async {
    const goal = Goal(
      id: 'retry-goal',
      title: 'Try again',
      reason: 'Make sure failed requests can recover.',
    );

    repository.failNextRequest = true;

    final firstAttempt = await state.run(
      (repository) => repository.saveGoal(goal),
    );

    expect(firstAttempt, isFalse);
    expect(state.error, isNotNull);
    expect(state.busy, isFalse);

    expect(state.data!.goals.any((item) => item.id == goal.id), isFalse);

    final retry = await state.run((repository) => repository.saveGoal(goal));

    expect(retry, isTrue);
    expect(state.error, isNull);
    expect(state.busy, isFalse);

    expect(state.data!.goals.where((item) => item.id == goal.id).length, 1);
  });

  test('cannot delete another user’s community post', () async {
    final post = state.data!.posts.firstWhere(
      (post) => post.authorId != currentUserId,
    );

    final success = await state.run(
      (repository) => repository.deletePost(post.id),
    );

    expect(success, isFalse);

    expect(state.data!.posts.any((item) => item.id == post.id), isTrue);
  });
  test('successful write stays successful when refresh fails', () async {
    const goal = Goal(
      id: 'saved-before-refresh-failure',
      title: 'Build a reliable app',
      reason: 'Understand the difference between saving and refreshing.',
    );

    final success = await state.run((repository) async {
      await repository.saveGoal(goal);

      // Make only the following reload fail.
      (repository as MemoryAnchorRepository).failNextRequest = true;
    });

    expect(success, isTrue);
    expect(state.busy, isFalse);

    expect(
      state.error,
      'Your change was saved, but the latest data '
      'could not be loaded. Refresh to see it.',
    );

    await state.load();

    expect(state.error, isNull);

    expect(state.data!.goals.where((item) => item.id == goal.id).length, 1);
  });
}
