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
import 'legal/legal_texts.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
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

enum _AgreementDocType { user, privacy }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) => false;

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
  bool _agreementReady = false;
  bool _agreementAccepted = false;
  bool _agreementChecked = false;
  bool _permissionReady = false;
  bool _checkingPermission = false;
  bool _locationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;
  bool _canInstallPackages = true;
  bool _userAgreementReadToEnd = false;
  bool _privacyPolicyReadToEnd = false;
  String? _agreementDocTitle;
  String? _agreementDocContent;
  _AgreementDocType? _agreementDocType;
  bool _showLaunchOverlay = true;
  double _launchOverlayOpacity = 0;
  Offset _launchOverlayOffset = const Offset(0, 0.08);
  bool _recheckPermissionOnResume = false;
  bool get _canCheckAgreement => _userAgreementReadToEnd && _privacyPolicyReadToEnd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(_onAppEvent);
    unawaited(_loadAgreementState());
    unawaited(_refreshPermissionState());
    unawaited(_playLaunchOverlay());
    // 启动阶段优先保证首屏可交互，再延后非关键网络任务，提升体感启动速度。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        scheduleStartupAppUpdate(appNavigatorKey);
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
      if (Platform.isIOS && _recheckPermissionOnResume) {
        _recheckPermissionOnResume = false;
        unawaited(_refreshPermissionState(userInitiated: true));
      } else {
        unawaited(_refreshPermissionState());
      }
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

  Future<void> _loadAgreementState() async {
    final accepted = widget.app.storage.legalAgreementAccepted;
    if (!mounted) return;
    setState(() {
      _agreementAccepted = accepted;
      _agreementReady = true;
    });
  }

  Future<void> _acceptAgreement() async {
    if (!_agreementChecked || !_canCheckAgreement) return;
    await widget.app.storage.setLegalAgreementAccepted(true);
    if (!mounted) return;
    setState(() {
      _agreementAccepted = true;
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

  Future<void> _refreshPermissionState({bool userInitiated = false}) async {
    if (_checkingPermission) return;
    _checkingPermission = true;
    bool locEnabled = _locationServiceEnabled;
    LocationPermission locPermission = _locationPermission;
    var canInstall = _canInstallPackages;

    try {
      // iOS 启动期至少要读取一次权限状态，否则会一直显示未授权。
      // 为了稳妥，冷启动只做 checkPermission，不做更重的系统设置检查。
      if (Platform.isIOS && !userInitiated) {
        try {
          locPermission = await Geolocator.checkPermission();
          // 冷启动仅用于放行判定，避免出现“未开启定位服务”误导。
          locEnabled = true;
        } catch (_) {}
      } else {
        try {
          locEnabled = await Geolocator.isLocationServiceEnabled();
          locPermission = await Geolocator.checkPermission();
        } catch (_) {}
      }

      if (Platform.isAndroid) {
        try {
          canInstall = await AndroidPackageInstaller.canRequestPackageInstalls();
        } catch (_) {
          canInstall = false;
        }
      }

      final locGranted = locPermission == LocationPermission.whileInUse ||
          locPermission == LocationPermission.always;
      // 不再强制要求系统定位总开关必须打开：
      // 已授权即可进入应用，关闭定位仅影响坐标采集，不影响核心功能使用。
      final ready = locGranted && canInstall;

      if (!mounted) return;
      setState(() {
        _locationServiceEnabled = locEnabled;
        _locationPermission = locPermission;
        _canInstallPackages = canInstall;
        _permissionReady = ready;
      });
    } finally {
      _checkingPermission = false;
    }
  }

  Future<void> _handleGrantLocation() async {
    try {
      await _refreshPermissionState(userInitiated: true);

      if (Platform.isIOS) {
        if (_locationPermission == LocationPermission.denied) {
          await Geolocator.requestPermission();
          await _refreshPermissionState(userInitiated: true);
          return;
        }
        _recheckPermissionOnResume = true;
        await Geolocator.openAppSettings();
        await _refreshPermissionState(userInitiated: true);
        return;
      }

      if (!_locationServiceEnabled) {
        _recheckPermissionOnResume = true;
        await Geolocator.openLocationSettings();
        await _refreshPermissionState(userInitiated: true);
        return;
      }
      if (_locationPermission == LocationPermission.denied ||
          _locationPermission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
        await _refreshPermissionState(userInitiated: true);
        return;
      }
      _recheckPermissionOnResume = true;
      await Geolocator.openAppSettings();
      await _refreshPermissionState(userInitiated: true);
    } catch (_) {
      if (mounted) {
        TopToast.show(context, '定位权限检查失败，请稍后重试', error: true);
      }
    }
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
                          if (!_permissionReady || !_agreementReady || !_agreementAccepted)
                            Positioned.fill(
                              child: _PreflightGatePager(
                                permissionReady: _permissionReady,
                                permissionPage: _PermissionGateView(
                                  locationServiceEnabled: _locationServiceEnabled,
                                  locationPermission: _locationPermission,
                                  needInstallPermission: Platform.isAndroid && !_canInstallPackages,
                                  checking: _checkingPermission,
                                  onGrantLocation: _handleGrantLocation,
                                  onGrantInstallPermission:
                                      Platform.isAndroid ? _handleGrantInstallPermission : null,
                                  onRetry: () => _refreshPermissionState(userInitiated: true),
                                ),
                                agreementPage: _AgreementGateView(
                                  loading: !_agreementReady,
                                  checked: _agreementChecked,
                                  canCheck: _canCheckAgreement,
                                  userAgreementReadToEnd: _userAgreementReadToEnd,
                                  privacyPolicyReadToEnd: _privacyPolicyReadToEnd,
                                  onCheckedChanged: (v) => setState(() => _agreementChecked = v),
                                  onAccept: _acceptAgreement,
                                  onOpenUserAgreement: () => setState(() {
                                    _agreementDocType = _AgreementDocType.user;
                                    _agreementDocTitle = '用户协议';
                                    _agreementDocContent = userAgreementText;
                                  }),
                                  onOpenPrivacyPolicy: () => setState(() {
                                    _agreementDocType = _AgreementDocType.privacy;
                                    _agreementDocTitle = '隐私政策';
                                    _agreementDocContent = privacyPolicyText;
                                  }),
                                  onExitApp: () => SystemNavigator.pop(),
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: _agreementDocTitle == null || _agreementDocContent == null,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                reverseDuration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.fastOutSlowIn,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  final eased = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.fastOutSlowIn,
                                    reverseCurve: Curves.easeInCubic,
                                  );
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 0.02),
                                    end: Offset.zero,
                                  ).animate(eased);
                                  final scale = Tween<double>(begin: 0.985, end: 1).animate(eased);
                                  return FadeTransition(
                                    opacity: Tween<double>(begin: 0.0, end: 1.0).animate(eased),
                                    child: SlideTransition(
                                      position: slide,
                                      child: ScaleTransition(scale: scale, child: child),
                                    ),
                                  );
                                },
                                child: (_agreementDocTitle != null && _agreementDocContent != null)
                                    ? KeyedSubtree(
                                        key: ValueKey('agreement-doc-overlay-${_agreementDocType?.name ?? 'none'}'),
                                        child: _AgreementDocOverlay(
                                          title: _agreementDocTitle!,
                                          content: _agreementDocContent!,
                                          onScrolledToEnd: () => setState(() {
                                            if (_agreementDocType == _AgreementDocType.user) {
                                              _userAgreementReadToEnd = true;
                                            } else if (_agreementDocType ==
                                                _AgreementDocType.privacy) {
                                              _privacyPolicyReadToEnd = true;
                                            }
                                          }),
                                          onClose: () => setState(() {
                                            _agreementDocType = null;
                                            _agreementDocTitle = null;
                                            _agreementDocContent = null;
                                          }),
                                        ),
                                      )
                                    : const SizedBox.shrink(key: ValueKey('agreement-doc-empty')),
                              ),
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
                      bottomNavigationBar: (_permissionReady && _agreementAccepted)
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

class _PreflightGatePager extends StatefulWidget {
  const _PreflightGatePager({
    required this.permissionReady,
    required this.permissionPage,
    required this.agreementPage,
  });

  final bool permissionReady;
  final Widget permissionPage;
  final Widget agreementPage;

  @override
  State<_PreflightGatePager> createState() => _PreflightGatePagerState();
}

class _PreflightGatePagerState extends State<_PreflightGatePager> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: 0);
    _page = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Future<void> goToAgreement() async {
      if (!widget.permissionReady) return;
      await _controller.animateToPage(
        1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.fastOutSlowIn,
      );
    }

    return Stack(
      children: [
        PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _page = index),
          children: [
            widget.permissionPage,
            widget.agreementPage,
          ],
        ),
        if (_page == 0)
          Positioned(
            left: 20,
            right: 20,
            bottom: 38,
            child: SafeArea(
              top: false,
              child: FilledButton.tonalIcon(
                onPressed: widget.permissionReady ? goToAgreement : null,
                icon: Icon(
                  widget.permissionReady
                      ? Icons.arrow_forward_rounded
                      : Icons.checklist_rtl_rounded,
                ),
                label: Text(widget.permissionReady ? '下一步：阅读协议' : '先完成上方权限授权'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
      ],
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
    final allGranted = locGranted && !needInstallPermission;
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
              if (!allGranted)
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
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, size: 18, color: cs.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '权限已完成，点击下方“下一步：阅读协议”继续',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgreementGateView extends StatelessWidget {
  const _AgreementGateView({
    required this.loading,
    required this.checked,
    required this.canCheck,
    required this.userAgreementReadToEnd,
    required this.privacyPolicyReadToEnd,
    required this.onCheckedChanged,
    required this.onAccept,
    required this.onOpenUserAgreement,
    required this.onOpenPrivacyPolicy,
    required this.onExitApp,
  });

  final bool loading;
  final bool checked;
  final bool canCheck;
  final bool userAgreementReadToEnd;
  final bool privacyPolicyReadToEnd;
  final ValueChanged<bool> onCheckedChanged;
  final Future<void> Function() onAccept;
  final VoidCallback onOpenUserAgreement;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onExitApp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget statusChip(bool done) {
      final bg = done ? Colors.green.withValues(alpha: 0.14) : cs.surfaceContainerHighest;
      final fg = done ? Colors.green.shade700 : cs.onSurfaceVariant;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          done ? '已读到底' : '未完成',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg),
        ),
      );
    }

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '请先同意协议',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '首次使用前，请先阅读并同意《用户协议》与《隐私政策》。',
                      style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 18),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.description_rounded),
                            title: const Text('用户协议', style: TextStyle(fontWeight: FontWeight.w800)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                statusChip(userAgreementReadToEnd),
                                const SizedBox(width: 6),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            onTap: onOpenUserAgreement,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.privacy_tip_rounded),
                            title: const Text('隐私政策', style: TextStyle(fontWeight: FontWeight.w800)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                statusChip(privacyPolicyReadToEnd),
                                const SizedBox(width: 6),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            onTap: onOpenPrivacyPolicy,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: checked,
                      onChanged: canCheck ? (v) => onCheckedChanged(v ?? false) : null,
                      title: const Text(
                        '我已阅读并同意《用户协议》与《隐私政策》',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (!canCheck)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Text(
                          '请先分别打开两个协议并滚动到底，才可勾选同意',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: checked && canCheck ? onAccept : null,
                      child: const Text('同意并继续'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: onExitApp,
                      child: const Text('不同意并退出'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AgreementDocOverlay extends StatefulWidget {
  const _AgreementDocOverlay({
    required this.title,
    required this.content,
    required this.onScrolledToEnd,
    required this.onClose,
  });

  final String title;
  final String content;
  final VoidCallback onScrolledToEnd;
  final VoidCallback onClose;

  @override
  State<_AgreementDocOverlay> createState() => _AgreementDocOverlayState();
}

class _AgreementDocOverlayState extends State<_AgreementDocOverlay> {
  late final ScrollController _scrollController;
  bool _reportedEnd = false;
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    final maxExtent = position.maxScrollExtent;
    final current = position.pixels.clamp(0.0, maxExtent);
    final progress = maxExtent <= 1 ? 1.0 : (current / maxExtent).clamp(0.0, 1.0);
    if ((progress - _scrollProgress).abs() >= 0.01 && mounted) {
      setState(() => _scrollProgress = progress);
    }
    if (_reportedEnd) return;
    if (maxExtent <= 1 || position.pixels >= maxExtent - 24) {
      _reportedEnd = true;
      if (mounted && _scrollProgress < 1) {
        setState(() => _scrollProgress = 1);
      }
      widget.onScrolledToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 64),
                        child: SelectableText(
                          widget.content,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.62,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: cs.surfaceContainer.withValues(alpha: 0.92),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _reportedEnd
                                    ? Icons.check_circle_rounded
                                    : Icons.keyboard_double_arrow_down_rounded,
                                size: 18,
                                color: _reportedEnd ? Colors.green.shade700 : cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _reportedEnd
                                      ? '已阅读到底，可以返回勾选同意'
                                      : '继续下滑到底以解锁勾选（${(_scrollProgress * 100).toInt()}%）',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
