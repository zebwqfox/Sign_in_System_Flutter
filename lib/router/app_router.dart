import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/history_detail_screen.dart';
import '../screens/developer_profile_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/legal_document_screen.dart';
import '../screens/login_screen.dart';
import '../screens/logs_screen.dart';
import '../screens/schedule_manager_screen.dart';
import '../screens/student_manager_screen.dart';
import '../screens/history_record_edit_screen.dart';
import '../screens/session_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_detail_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/summary_screen.dart';
import '../legal/legal_texts.dart';
import '../state/app_controller.dart';
import 'page_transitions.dart';

GoRouter createRouter(
  AppController app,
  GlobalKey<NavigatorState> navigatorKey, {
  List<NavigatorObserver> observers = const [],
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    observers: observers,
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
        pageBuilder: (context, state) =>
            fadePage<void>(key: state.pageKey, name: state.matchedLocation, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => fadeSlidePage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const HomeScreen(),
          slideBegin: const Offset(0.03, 0),
        ),
      ),
      GoRoute(
        path: '/session',
        pageBuilder: (context, state) =>
            secondaryPage<void>(key: state.pageKey, name: state.matchedLocation, child: const SessionScreen()),
      ),
      GoRoute(
        path: '/summary',
        pageBuilder: (context, state) =>
            secondaryPage<void>(key: state.pageKey, name: state.matchedLocation, child: const SummaryScreen()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, name: state.matchedLocation, child: const HistoryScreen()),
      ),
      GoRoute(
        path: '/history/detail/:sessionId',
        pageBuilder: (context, state) {
          final raw = state.pathParameters['sessionId']!;
          final sessionId = Uri.decodeComponent(raw);
          return secondaryPage<void>(
            key: state.pageKey,
            name: state.matchedLocation,
            child: HistoryDetailScreen(sessionId: sessionId, isAdmin: true),
          );
        },
      ),
      GoRoute(
        path: '/history/detail/:sessionId/edit/:recordId',
        pageBuilder: (context, state) {
          final rawSessionId = state.pathParameters['sessionId']!;
          final sessionId = Uri.decodeComponent(rawSessionId);
          final recordId = state.pathParameters['recordId']!;
          return secondaryPage<bool>(
            key: state.pageKey,
            name: state.matchedLocation,
            child: HistoryRecordEditScreen(sessionId: sessionId, recordId: recordId),
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
          name: state.matchedLocation,
          child: const Scaffold(body: Center(child: Text('无效的分享链接'))),
        ),
      ),
      GoRoute(
        path: '/share/detail/:sessionId',
        pageBuilder: (context, state) {
          final raw = state.pathParameters['sessionId']!;
          final sessionId = Uri.decodeComponent(raw);
          return secondaryPage<void>(
            key: state.pageKey,
            name: state.matchedLocation,
            child: HistoryDetailScreen(sessionId: sessionId, isAdmin: false),
          );
        },
      ),
      GoRoute(
        path: '/stats',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, name: state.matchedLocation, child: const StatsScreen()),
      ),
      GoRoute(
        path: '/stats/detail/:studentId/:studentName',
        pageBuilder: (context, state) {
          // go_router 对 pathParameters 已做了一次解码，避免二次 decodeComponent 导致非法百分号异常
          final studentId = state.pathParameters['studentId']!;
          final studentName = state.pathParameters['studentName']!;
          return secondaryPage<void>(
            key: state.pageKey,
            name: state.matchedLocation,
            child: StatsDetailScreen(studentId: studentId, studentName: studentName),
          );
        },
      ),
      GoRoute(
        path: '/logs',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, name: state.matchedLocation, child: const LogsScreen()),
      ),
      GoRoute(
        path: '/students/manage',
        pageBuilder: (context, state) => secondaryPage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const StudentManagerScreen(),
        ),
      ),
      GoRoute(
        path: '/schedule/manage',
        pageBuilder: (context, state) => secondaryPage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const ScheduleManagerScreen(),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            fadeSlidePage<void>(key: state.pageKey, name: state.matchedLocation, child: const SettingsScreen()),
      ),
      GoRoute(
        path: '/about/developer',
        pageBuilder: (context, state) => secondaryPage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const DeveloperProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/legal/user-agreement',
        pageBuilder: (context, state) => secondaryPage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const LegalDocumentScreen(
            title: '用户协议',
            content: userAgreementText,
          ),
        ),
      ),
      GoRoute(
        path: '/legal/privacy-policy',
        pageBuilder: (context, state) => secondaryPage<void>(
          key: state.pageKey,
          name: state.matchedLocation,
          child: const LegalDocumentScreen(
            title: '隐私政策',
            content: privacyPolicyText,
          ),
        ),
      ),
    ],
  );
}
