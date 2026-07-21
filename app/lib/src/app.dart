import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell_screen.dart';
import 'theme.dart';

class TonyoApp extends StatefulWidget {
  const TonyoApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<TonyoApp> createState() => _TonyoAppState();
}

class _TonyoAppState extends State<TonyoApp> {
  late final AppController controller = widget.controller ?? AppController();

  @override
  void initState() {
    super.initState();
    if (!controller.isReady) controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Tonyo',
        debugShowCheckedModeBanner: false,
        theme: buildTonyoTheme(),
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (!controller.isReady) return const _LoadingScreen();
            return controller.onboardingComplete
                ? const ShellScreen()
                : const OnboardingScreen();
          },
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
