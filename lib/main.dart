import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'services/easter_egg_audio_service.dart';
import 'services/audit_service.dart';
import 'services/audit_upload_service.dart';
import 'services/android_package_installer.dart';
import 'services/storage_service.dart';
import 'state/root_modal_barrier.dart';
import 'state/app_controller.dart';
import 'utils/startup_update_check.dart';
import 'widgets/bottom_function_bar.dart';
import 'widgets/top_toast.dart';

final GlobalKey<ScaffoldMessengerState> rootMessenger = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

bool _isAudioPlayersMissingPlugin(Object error) {
  if (error is! MissingPluginException) return false;
  final msg = error.message ?? '';
  return msg.contains('xyz.luan/audioplayers');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  FlutterError.onError = (details) {
    if (_isAudioPlayersMissingPlugin(details.exception)) {
      debugPrint('audioplayers plugin not ready: ${details.exception}');
      return;
    }
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isAudioPlayersMissingPlugin(error)) {
      debugPrint('audioplayers plugin not ready: $error');
      return true;
    }
    return false;
  };

  final storage = await StorageService.create();
  await AuditService.instance.init(storage);
  AuditUploadService.instance.init(storage);
  final api = ApiService(baseUrl: AppConfig.apiBaseUrl, authStorage: storage);
  final app = AppController(api: api, storage: storage);
  final router = createRouter(
    app,
    appNavigatorKey,
    observers: [AuditNavigatorObserver()],
  );

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

class _SignInRootState extends State<_SignInRoot> with WidgetsBindingObserver {
  bool _permissionReady = false;
  bool _checkingPermission = false;
  bool _locationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;
  bool _canInstallPackages = true;
  bool _showLaunchOverlay = true;
  double _launchOverlayOpacity = 0;
  Offset _launchOverlayOffset = const Offset(0, 0.08);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_onAppEvent);
    unawaited(_refreshPermissionState(autoRequestLocation: true));
    unawaited(_playLaunchOverlay());
    // 启动阶段优先保证首屏可交互，再延后非关键网络任务，提升体感启动速度。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        scheduleStartupAppUpdate(appNavigatorKey);
      }));
      unawaited(Future<void>.delayed(const Duration(milliseconds: 900), () async {
        await EasterEggAudioService.instance.prefetchSilently();
      }));
      unawaited(Future<void>.delayed(const Duration(milliseconds: 1300), () async {
        await AuditUploadService.instance.uploadOnStartupSilently();
      }));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(_onAppEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionState());
    }
  }

  void _onAppEvent() {
    final msg = widget.app.snackMessage;
    if (msg == null) return;
    final err = widget.app.snackError;
    widget.app.clearSnack();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TopToast.show(context, msg, error: err);
    });
  }

  Future<void> _playLaunchOverlay() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    setState(() {
      _launchOverlayOpacity = 1;
      _launchOverlayOffset = Offset.zero;
    });
    await Future<void>.delayed(const Duration(milliseconds: 620));
    if (!mounted) return;
    setState(() {
      _launchOverlayOpacity = 0;
      _launchOverlayOffset = const Offset(0, -0.03);
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      _showLaunchOverlay = false;
    });
  }

  Future<void> _refreshPermissionState({bool autoRequestLocation = false}) async {
    if (_checkingPermission) return;
    _checkingPermission = true;
    bool locEnabled = false;
    LocationPermission locPermission = LocationPermission.denied;
    var canInstall = true;

    try {
      locEnabled = await Geolocator.isLocationServiceEnabled();
      locPermission = await Geolocator.checkPermission();
      if (autoRequestLocation && locEnabled && locPermission == LocationPermission.denied) {
        locPermission = await Geolocator.requestPermission();
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        canInstall = await AndroidPackageInstaller.canRequestPackageInstalls();
      } catch (_) {
        canInstall = false;
      }
    }

    final locGranted = locPermission == LocationPermission.whileInUse ||
        locPermission == LocationPermission.always;
    final ready = locEnabled && locGranted && canInstall;

    if (!mounted) return;
    setState(() {
      _locationServiceEnabled = locEnabled;
      _locationPermission = locPermission;
      _canInstallPackages = canInstall;
      _permissionReady = ready;
    });
    _checkingPermission = false;
  }

  Future<void> _handleGrantLocation() async {
    if (!_locationServiceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }
    if (_locationPermission == LocationPermission.denied) {
      await Geolocator.requestPermission();
      await _refreshPermissionState();
      return;
    }
    await Geolocator.openAppSettings();
  }

  Future<void> _handleGrantInstallPermission() async {
    await AndroidPackageInstaller.openUnknownSourcesSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.app,
      child: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              final useCustom = widget.app.themeColorMode == 'custom';
              final seedColor = Color(widget.app.themeSeedColor);
              final lightTheme = useCustom
                  ? AppTheme.lightFromSeed(seedColor)
                  : (lightDynamic != null ? AppTheme.lightFromDynamic(lightDynamic) : AppTheme.light);
              final darkTheme = useCustom
                  ? AppTheme.darkFromSeed(seedColor)
                  : (darkDynamic != null ? AppTheme.darkFromDynamic(darkDynamic) : AppTheme.dark);

              return MaterialApp.router(
                scaffoldMessengerKey: rootMessenger,
                title: '签到助手',
                theme: lightTheme,
                darkTheme: darkTheme,
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
                    ),
                    child: Scaffold(
                      // 这里的容器颜色必须跟随主题，否则在 Stack 切换时会有闪烁
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      body: Stack(
                        children: [
                          child ?? const SizedBox.shrink(),
                          if (!_permissionReady)
                            Positioned.fill(
                              child: _PermissionGateView(
                                locationServiceEnabled: _locationServiceEnabled,
                                locationPermission: _locationPermission,
                                needInstallPermission: Platform.isAndroid && !_canInstallPackages,
                                checking: _checkingPermission,
                                onGrantLocation: _handleGrantLocation,
                                onGrantInstallPermission:
                                    Platform.isAndroid ? _handleGrantInstallPermission : null,
                                onRetry: _refreshPermissionState,
                              ),
                            ),
                          if (_showLaunchOverlay)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                  opacity: _launchOverlayOpacity,
                                  child: AnimatedSlide(
                                    duration: const Duration(milliseconds: 320),
                                    curve: Curves.easeOutCubic,
                                    offset: _launchOverlayOffset,
                                    child: ColoredBox(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      child: SizedBox.expand(
                                        child: Image.asset(
                                          'assets/startup.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      // 底栏内部根据路由自行决定显示/隐藏与指示效果
                      bottomNavigationBar: _permissionReady
                          ? ValueListenableBuilder<bool>(
                              valueListenable: rootModalBarrierVisible,
                              builder: (context, covered, _) {
                                return Stack(
                                  children: [
                                    BottomFunctionBar(light: lightContent, router: widget.router),
                                    if (covered)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            )
                          : null,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _PermissionGateView extends StatelessWidget {
  const _PermissionGateView({
    required this.locationServiceEnabled,
    required this.locationPermission,
    required this.needInstallPermission,
    required this.checking,
    required this.onGrantLocation,
    required this.onGrantInstallPermission,
    required this.onRetry,
  });

  final bool locationServiceEnabled;
  final LocationPermission locationPermission;
  final bool needInstallPermission;
  final bool checking;
  final Future<void> Function() onGrantLocation;
  final Future<void> Function()? onGrantInstallPermission;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locGranted = locationPermission == LocationPermission.whileInUse ||
        locationPermission == LocationPermission.always;
    String locStatus() {
      if (!locationServiceEnabled) return '未开启定位服务';
      return switch (locationPermission) {
        LocationPermission.always => '已授权（始终）',
        LocationPermission.whileInUse => '已授权（使用期间）',
        LocationPermission.deniedForever => '已永久拒绝',
        LocationPermission.denied => '未授权',
        _ => '未授权',
      };
    }

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '请先完成权限授权',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                '该应用要求安装后先授予必要权限，否则无法继续使用。',
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on_rounded),
                  title: const Text('定位权限', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(locStatus()),
                  trailing: FilledButton(
                    onPressed: checking || locGranted ? null : onGrantLocation,
                    child: Text(locGranted ? '已授权' : '去授权'),
                  ),
                ),
              ),
              if (onGrantInstallPermission != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.install_mobile_rounded),
                    title: const Text('安装未知应用权限', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(needInstallPermission ? '用于应用内更新安装' : '已授权'),
                    trailing: FilledButton(
                      onPressed: checking || !needInstallPermission ? null : onGrantInstallPermission,
                      child: Text(needInstallPermission ? '去授权' : '已授权'),
                    ),
                  ),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: checking ? null : onRetry,
                icon: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('我已授权，重新检查'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
