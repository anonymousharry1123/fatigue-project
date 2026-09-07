import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/onboarding_screen.dart';
import 'screens/privacy_center_screen.dart';
import 'screens/shell_screen.dart';
import 'theme.dart';

class TonyoApp extends StatefulWidget {
  const TonyoApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<TonyoApp> createState() => _TonyoAppState();
}

class _TonyoAppState extends State<TonyoApp> with WidgetsBindingObserver {
  late final AppController controller = widget.controller ?? AppController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!controller.isReady) controller.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && controller.isReady) {
      controller.handleAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => MaterialApp(
          // Reset the navigator as well as the home screen: a pushed private
          // route must not remain visible or reachable with Back after sign-out.
          key: ValueKey((
            controller.isSignedOut,
            controller.deletionPending,
            controller.onboardingComplete && controller.privacyReviewRequired,
          )),
          title: 'Tonyo',
          debugShowCheckedModeBanner: false,
          scrollBehavior: const TonyoScrollBehavior(),
          theme: buildTonyoTheme(),
          home: !controller.isReady
              ? const _LoadingScreen()
              : !controller.isSignedOut &&
                    (controller.deletionPending ||
                        ((controller.onboardingComplete ||
                                (controller.isCloudAuthenticated &&
                                    controller.cloudSyncError == null)) &&
                            controller.privacyReviewRequired))
              ? PrivacyCenterScreen(controller: controller, requireReview: true)
              : controller.onboardingComplete && !controller.isSignedOut
              ? const ShellScreen()
              : const OnboardingScreen(),
        ),
      ),
    );
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
