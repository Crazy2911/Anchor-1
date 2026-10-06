import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'remote_reflection_assistant.dart';
import 'app_state.dart';
import 'editor_screen.dart';
import 'post_assistant.dart';
import 'screens.dart';
import 'api_feed_repository.dart';
import 'planning_assistant.dart';
import 'auth_state.dart';
import 'login_screen.dart';
import 'discussion_assistant.dart';
import 'focus_assistant.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthState(),
      child: const SessionGate(),
    ),
  );
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final session = auth.session;

    if (session == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Anchor',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF246B60),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        home: const LoginScreen(),
      );
    }

    return ChangeNotifierProvider<AppState>(
      key: ValueKey(session.token),
      lazy: false,
      create: (_) {
        final state = AppState(
          focusAssistant: RemoteFocusAssistant(
          baseUrl: apiBaseUrl,
          token: session.token,
        ),
          discussionAssistant: RemoteDiscussionAssistant(
          baseUrl: apiBaseUrl,
          token: session.token,
        ),
          userId: session.userId,
          repository: ApiFeedRepository(
            baseUrl: apiBaseUrl,
            token: session.token,
            userId: session.userId,
          ),
          assistant: RemoteReflectionAssistant(
            baseUrl: apiBaseUrl,
            token: session.token,
          ),
          postAssistant: RemotePostAssistant(
          baseUrl: apiBaseUrl,
          token: session.token,
        ),
          planner: RemotePlanningAssistant(
            baseUrl: apiBaseUrl,
            token: session.token,
          ),
        );

        state.load();

        return state;
      },
      child: const AnchorApp(),
    );
  }
}

class AnchorApp extends StatelessWidget {
  const AnchorApp({super.key});

  ThemeData _theme(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF246B60),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF6F8F5)
          : const Color(0xFF111916),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return MaterialApp(
      title: 'Anchor',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: state.themeMode,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        Widget page;

        switch (settings.name) {
          case '/':
            page = const HomeScreen();
            break;

          case '/edit':
            final arguments = settings.arguments;
            page = arguments is EditorArgs
                ? EditorScreen(args: arguments)
                : const MissingScreen();
            break;

          case '/post':
            final arguments = settings.arguments;
            page = arguments is String
                ? PostDetailScreen(postId: arguments)
                : const MissingScreen();
            break;

          case '/saved':
            page = const SavedScreen();
            break;

          default:
            page = const MissingScreen();
        }

        return PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (MediaQuery.of(context).disableAnimations) {
              return child;
            }

            final easedAnimation = animation.drive(
              CurveTween(curve: Curves.easeOutCubic),
            );

            final slideAnimation = animation.drive(
              Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
            );

            return FadeTransition(
              opacity: easedAnimation,
              child: SlideTransition(position: slideAnimation, child: child),
            );
          },
        );
      },
    );
  }
}
