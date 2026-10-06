import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

class AuthSession {
  final String token;
  final String userId;
  final String username;
  final String displayName;

  const AuthSession({
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final token = json['token'];

    if (user is! Map<String, dynamic> || token is! String || token.isEmpty) {
      throw const FormatException('Invalid login response.');
    }

    String requiredText(String key) {
      final value = user[key];

      if (value is! String || value.isEmpty) {
        throw const FormatException('Invalid account data.');
      }

      return value;
    }

    return AuthSession(
      token: token,
      userId: requiredText('id'),
      username: requiredText('username'),
      displayName: requiredText('displayName'),
    );
  }
}

class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);
}

class AuthState extends ChangeNotifier {
  AuthSession? session;
  bool busy = false;
  String? error;

  String get _root => apiBaseUrl.replaceFirst(RegExp(r'/$'), '');

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final client = http.Client();

    try {
      final response = await client
          .post(
            Uri.parse('$_root$path'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 15));

      final json = jsonDecode(utf8.decode(response.bodyBytes));

      if (json is! Map<String, dynamic>) {
        throw const FormatException('Invalid server response.');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthFailure(
          json['message'] is String
              ? json['message'] as String
              : 'The request failed. Please try again.',
        );
      }

      return json;
    } on TimeoutException {
      throw const AuthFailure(
        'The request timed out. If registration may have completed, '
        'try signing in with the same credentials.',
      );
    } on http.ClientException {
      throw const AuthFailure(
        'Cannot reach the server. Check that Python is running.',
      );
    } finally {
      client.close();
    }
  }

  Future<void> authenticate({
    required bool register,
    required String username,
    required String password,
    String? displayName,
  }) async {
    if (busy) return;

    busy = true;
    error = null;
    notifyListeners();

    try {
      final response = await _post(
        register ? '/auth/register' : '/auth/login',
        body: {
          'username': username.trim().toLowerCase(),
          'password': password,
          if (register) 'displayName': displayName?.trim() ?? '',
        },
      );

      session = AuthSession.fromJson(response);
    } on AuthFailure catch (failure) {
      error = failure.message;
    } on FormatException {
      error = 'Unexpected login response. Check the backend version.';
    } catch (_) {
      error = 'Unable to sign in. Please try again.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final current = session;

    if (busy || current == null) return;

    busy = true;
    error = null;
    notifyListeners();

    try {
      await _post('/auth/logout', token: current.token);

      session = null;
    } on AuthFailure catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'Sign-out failed. Check your connection and try again.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }
}
