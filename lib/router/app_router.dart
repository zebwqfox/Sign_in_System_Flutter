import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/history_detail_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/logs_screen.dart';
import '../screens/session_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/summary_screen.dart';
import '../state/app_controller.dart';
import 'page_transitions.dart';

GoRouter createRouter(AppController app, GlobalKey<NavigatorState> navigatorKey) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/login',
    refreshListenable: app.authListenable,
    redirect: (context, state) {
      final path = state.matchedLocation;
      final share = path == '/share';
      final loggedIn = app.isLoggedIn;
      if (!loggedIn && path != '/login' && !share) {
        return '/login';
      }
      if (loggedIn && path == '/login') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => fadePage<void>(key: state.pageKey, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, child: const HomeScreen(), slideBegin: const Offset(0.03, 0)),
      ),
      GoRoute(
        path: '/session',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, child: const SessionScreen(), forward: const Duration(milliseconds: 240)),
      ),
      GoRoute(
        path: '/summary',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, child: const SummaryScreen(), slideBegin: const Offset(0, 0.03)),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, child: const HistoryScreen()),
      ),
      GoRoute(
        path: '/history/detail/:sessionId',
        pageBuilder: (context, state) {
          final raw = state.pathParameters['sessionId']!;
          final sessionId = Uri.decodeComponent(raw);
          return fadeSlidePage<void>(
            key: state.pageKey,
            child: HistoryDetailScreen(sessionId: sessionId, isAdmin: true),
          );
        },
      ),
      GoRoute(
        path: '/share',
        redirect: (context, state) {
          final id = state.uri.queryParameters['share_id'];
          if (id != null && id.isNotEmpty) {
            return '/share/detail/${Uri.encodeComponent(id)}';
          }
          return null;
        },
        pageBuilder: (context, state) => fadeSlidePage<void>(
          key: state.pageKey,
          child: const Scaffold(body: Center(child: Text('无效的分享链接'))),
        ),
      ),
      GoRoute(
        path: '/share/detail/:sessionId',
        pageBuilder: (context, state) {
          final raw = state.pathParameters['sessionId']!;
          final sessionId = Uri.decodeComponent(raw);
          return fadeSlidePage<void>(
            key: state.pageKey,
            child: HistoryDetailScreen(sessionId: sessionId, isAdmin: false),
          );
        },
      ),
      GoRoute(
        path: '/stats',
        pageBuilder: (context, state) => fadeSlidePage<void>(key: state.pageKey, child: const StatsScreen()),
      ),
      GoRoute(
        path: '/logs',
        pageBuilder: (context, state) => fadeSlidePage<void>(key: state.pageKey, child: const LogsScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => fadeSlidePage<void>(key: state.pageKey, child: const SettingsScreen()),
      ),
    ],
  );
}
