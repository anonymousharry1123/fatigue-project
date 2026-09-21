import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'screens/onboarding_screen.dart';
import 'screens/privacy_center_screen.dart';
import 'screens/shell_screen.dart';
import 'theme.dart';
import 'theme_controller.dart';

class TonyoApp extends StatefulWidget {
  const TonyoApp({super.key, this.controller, this.themeController});

  final AppController? controller;
  final ThemeController? themeController;

  @override
  State<TonyoApp> createState() => _TonyoAppState();
}

class _TonyoAppState extends State<TonyoApp> with WidgetsBindingObserver {
  late final AppController controller = widget.controller ?? AppController();
  late final ThemeController themeController =
      widget.themeController ?? ThemeController();
  late final Listenable _appChanges = Listenable.merge([
    controller,
    themeController,
  ]);
  late (int, String?) _navigationSession;
  (int, String?)? _pendingCoachTap;
  int? _coachOpenRequest;
  int _notificationRequestSequence = 0;
  Object? _navigatorIdentity;
  CoachNotificationNavigation _notificationNavigation =
      CoachNotificationNavigation();

  @override
  void initState() {
    super.initState();
    _navigationSession = (controller.sessionRevision, controller.cloudUid);
    controller.addListener(_handleNotificationNavigation);
    WidgetsBinding.instance.addObserver(this);
    controller.setAppForeground(true);
    _initializeNotificationResponses();
    if (!controller.isReady) {
      controller.load().then((_) => controller.scheduleCloudRetry());
    }
  }

  Future<void> _initializeNotificationResponses() async {
    try {
      await controller.initializeNotificationResponses(_notificationTapped);
    } on Object {
      // Notification routing is optional; failed platform initialization must
      // not prevent sign-in, privacy review, or ordinary app navigation.
    }
  }

  void _notificationTapped(String payload) {
    if (!mounted || !_isGuidanceNotification(payload)) return;
    final session = (controller.sessionRevision, controller.cloudUid);
    if (session != _navigationSession) {
      _navigationSession = session;
      _coachOpenRequest = null;
    }
    _pendingCoachTap = session;
    _handleNotificationNavigation();
  }

  void _handleNotificationNavigation() {
    if (!mounted) return;
    final session = (controller.sessionRevision, controller.cloudUid);
    if (session != _navigationSession) {
      _navigationSession = session;
      _pendingCoachTap = null;
      _coachOpenRequest = null;
    }
    if (!controller.canOpenNotificationTarget) {
      _coachOpenRequest = null;
      return;
    }
    if (_pendingCoachTap != session) return;
    _pendingCoachTap = null;
    setState(() => _coachOpenRequest = ++_notificationRequestSequence);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setAppForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && controller.isReady) {
      controller.handleAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_handleNotificationNavigation);
    controller.setAppForeground(false);
    if (widget.controller == null) controller.dispose();
    if (widget.themeController == null) themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: themeController,
      child: AppScope(
        controller: controller,
        child: AnimatedBuilder(
          animation: _appChanges,
          builder: (context, _) {
            // Authentication can change before cloud hydration finishes. Keep
            // the welcome form (including its pending/error state) intact until
            // a private shell is actually available.
            final hasPrivateShell =
                controller.isReady &&
                controller.onboardingComplete &&
                !controller.isSignedOut &&
                !controller.deletionPending &&
                !controller.privacyReviewRequired;
            final navigatorIdentity = (
              hasPrivateShell ? controller.sessionRevision : null,
              hasPrivateShell ? controller.cloudUid : null,
              controller.isSignedOut,
              controller.deletionPending,
              controller.onboardingComplete && controller.privacyReviewRequired,
            );
            if (_navigatorIdentity != navigatorIdentity) {
              _navigatorIdentity = navigatorIdentity;
              _notificationNavigation = CoachNotificationNavigation();
            }
            return MaterialApp(
              // Reset the navigator as well as the home screen: a pushed private
              // route must not remain visible or reachable with Back after sign-out.
              key: ValueKey(navigatorIdentity),
              navigatorObservers: [_notificationNavigation],
              title: 'Tonyo',
              debugShowCheckedModeBanner: false,
              scrollBehavior: const TonyoScrollBehavior(),
              theme: buildTonyoTheme(
                colors: themeController.preferences.colors,
                font: themeController.preferences.font,
              ),
              darkTheme: buildTonyoTheme(
                brightness: Brightness.dark,
                colors: themeController.preferences.colors,
                font: themeController.preferences.font,
              ),
              themeMode: themeController.preferences.mode,
              builder: (context, child) =>
                  AnnotatedRegion<SystemUiOverlayStyle>(
                    value: tonyoSystemOverlay(
                      Theme.of(context).brightness,
                      TonyoPalette.of(context),
                    ),
                    child: child!,
                  ),
              home: !controller.isReady
                  ? const _LoadingScreen()
                  : !controller.isSignedOut &&
                        (controller.deletionPending ||
                            ((controller.onboardingComplete ||
                                    (controller.isCloudAuthenticated &&
                                        controller.cloudSyncError == null)) &&
                                controller.privacyReviewRequired))
                  ? PrivacyCenterScreen(
                      controller: controller,
                      requireReview: true,
                    )
                  : controller.onboardingComplete && !controller.isSignedOut
                  ? ShellScreen(
                      coachOpenRequest: _coachOpenRequest,
                      notificationNavigation: _notificationNavigation,
                    )
                  : const OnboardingScreen(),
            );
          },
        ),
      ),
    );
  }
}

bool _isGuidanceNotification(String payload) {
  if (RegExp(
    r'^tonyo-guidance:\d{4}-\d{2}-\d{2}-(?:crash|recovery)$',
  ).hasMatch(payload)) {
    return true;
  }
  const coachPrefix = 'tonyo-guidance:coach:';
  if (!payload.startsWith(coachPrefix) || payload.length > 6000) return false;
  try {
    final id = Uri.decodeComponent(payload.substring(coachPrefix.length));
    return id.isNotEmpty && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(id);
  } on FormatException {
    return false;
  } on ArgumentError {
    return false;
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found');
    return scope!.notifier!;
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
