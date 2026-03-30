import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'state/app_controller.dart';
import 'utils/startup_update_check.dart';

final GlobalKey<ScaffoldMessengerState> rootMessenger = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final storage = await StorageService.create();
  final api = ApiService(baseUrl: AppConfig.apiBaseUrl, authStorage: storage);
  final app = AppController(api: api, storage: storage);
  final router = createRouter(app, appNavigatorKey);
  runApp(_SignInRoot(app: app, router: router));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(app.warmStartAfterFirstFrame());
  });
}

class _SignInRoot extends StatefulWidget {
  const _SignInRoot({required this.app, required this.router});

  final AppController app;
  final GoRouter router;

  @override
  State<_SignInRoot> createState() => _SignInRootState();
}

class _SignInRootState extends State<_SignInRoot> {
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_onAppEvent);
    scheduleStartupAppUpdate(rootMessenger, appNavigatorKey);
  }

  @override
  void dispose() {
    widget.app.removeListener(_onAppEvent);
    super.dispose();
  }

  void _onAppEvent() {
    final msg = widget.app.snackMessage;
    if (msg == null) return;
    final err = widget.app.snackError;
    widget.app.clearSnack();
    // 推到下一帧展示，避免在与 Provider 同一轮 element 更新栈里操作 ScaffoldMessenger。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      rootMessenger.currentState?.showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: err ? Colors.red : null),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.app,
      child: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          return MaterialApp.router(
            scaffoldMessengerKey: rootMessenger,
            title: '签到助手',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: widget.app.themeMode,
            routerConfig: widget.router,
            builder: (context, child) {
              final b = Theme.of(context).brightness;
              final lightContent = b == Brightness.light;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarDividerColor: Colors.transparent,
                  statusBarIconBrightness: lightContent ? Brightness.dark : Brightness.light,
                  systemNavigationBarIconBrightness: lightContent ? Brightness.dark : Brightness.light,
                  systemStatusBarContrastEnforced: false,
                  systemNavigationBarContrastEnforced: false,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
