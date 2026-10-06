import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:project/app_state.dart';
import 'package:project/editor_screen.dart';
import 'package:project/models.dart';
import 'package:project/repository.dart';

void main() {
  testWidgets('goal form rejects empty input and saves valid input', (
    tester,
  ) async {
    final state = AppState(
      repository: MemoryAnchorRepository(),
      assistant: DemoReflectionAssistant(),
    );

    await tester.runAsync(() async {
      await state.load();
    });

    addTearDown(state.dispose);

    final initialGoalCount = state.data!.goals.length;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const EditorScreen(
                            args: EditorArgs(kind: EditorKind.goal),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open goal editor'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open goal editor'));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Save');

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter at least 3 characters.'), findsOneWidget);

    expect(find.text('Enter at least 10 characters.'), findsOneWidget);

    expect(state.data!.goals.length, initialGoalCount);

    final fields = find.byType(TextFormField);

    await tester.enterText(fields.at(0), 'Build my Flutter skills');

    await tester.enterText(
      fields.at(1),
      'I want to understand every part of my application.',
    );

    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final savedGoals = state.data!.goals.where(
      (Goal goal) => goal.title == 'Build my Flutter skills',
    );

    expect(savedGoals.length, 1);
    expect(state.data!.goals.length, initialGoalCount + 1);

    // Successful saving returns to the previous screen.
    expect(find.text('Open goal editor'), findsOneWidget);
    expect(find.byType(EditorScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
