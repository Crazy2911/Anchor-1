import 'package:flutter/material.dart';
import 'planning_assistant.dart';
import 'models.dart';
import 'repository.dart';
import 'post_assistant.dart';
import 'discussion_assistant.dart';
import 'focus_assistant.dart';

class AppState extends ChangeNotifier {
  final AnchorRepository repository;
  final ReflectionAssistant assistant;
  final String userId;
  final PlanningAssistant? planner;
  final PostAssistant? postAssistant;
  final DiscussionAssistant? discussionAssistant;
  final FocusAssistant? focusAssistant;

  AppState({
    required this.repository,
    required this.assistant,
    this.userId = currentUserId,
    this.planner,
    this.postAssistant,
    this.discussionAssistant,
    this.focusAssistant,
  });

  AppData? data;
  bool loading = false;
  bool saving = false;
  String? error;

  ThemeMode themeMode = ThemeMode.light;

  bool get busy => loading || saving;
  bool get isDark => themeMode == ThemeMode.dark;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;

    loading = true;
    error = null;
    notifyListeners();

    try {
      data = await repository.load();
    } catch (exception) {
      error = _message(exception);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> run(
    Future<void> Function(AnchorRepository repository) operation,
  ) async {
    if (_disposed || busy) return false;

    saving = true;
    error = null;
    notifyListeners();

    try {
      // First, perform the write.
      try {
        await operation(repository);
      } catch (exception) {
        if (!_disposed) {
          error = _message(exception);
        }

        return false;
      }

      // The server acknowledged the write.
      if (_disposed) return true;

      // Then refresh the visible data separately.
      try {
        final refreshed = await repository.load();

        if (!_disposed) {
          data = refreshed;
        }
      } catch (_) {
        if (!_disposed) {
          error =
              'Your change was saved, but the latest data '
              'could not be loaded. Refresh to see it.';
        }
      }

      // A refresh failure must not turn a confirmed save into a failed save.
      return true;
    } finally {
      saving = false;

      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  String _message(Object exception) {
    if (exception is RepositoryException) return exception.message;
    return 'Something went wrong. Please try again.';
  }

  void toggleTheme() {
    themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
