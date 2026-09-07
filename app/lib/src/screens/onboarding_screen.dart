import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../account_error.dart';
import '../app.dart';
import '../models.dart';
import '../privacy_consent.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import 'privacy_center_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _pageController;
  bool _initializedPage = false;
  final _accountFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  int _page = 0;
  bool _acceptedPrivacy = false;
  PrivacyAgeBand? _ageBand;
  PrivacyRegion? _region;
  bool _ageLocked = false;
  bool _isSubmitting = false;
  bool _signInExisting = false;
  bool _existingAccountVerified = false;
  String? _accountError;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _role = 'Student athlete';
  String _goal = 'Balance focus and training';
  CoachPriority _coachPriority = CoachPriority.balanced;
  double _wake = 7;
  double _bed = 23;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedPage) return;
    _initializedPage = true;
    final controller = AppScope.of(context);
    // The privacy gate may replace this route after verified sign-in. Restore
    // only that authenticated, successfully loaded account's remaining setup;
    // never ask it to register or verify the password again.
    if (controller.isCloudAuthenticated &&
        !controller.isSignedOut &&
        !controller.onboardingComplete &&
        !controller.privacyReviewRequired &&
        controller.cloudSyncError == null) {
      _existingAccountVerified = true;
      _page = 3;
      _ageBand = controller.privacyConsent?.ageBand;
      _region = controller.privacyConsent?.region;
    }
    _pageController = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (value) => setState(() => _page = value),
              children: [
                _welcome(context),
                _privacyReview(context),
                _account(context),
                _profile(context),
                _schedule(context),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                if (_accountError != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _accountError!,
                      key: const Key('onboarding-account-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: index == _page ? 24 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? TonyoColors.primary
                            : TonyoColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting || (_page == 1 && _ageLocked)
                        ? null
                        : _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: TonyoColors.primary,
                    ),
                    child: _isSubmitting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Please wait…'),
                            ],
                          )
                        : Text(
                            _page == 0
                                ? AppScope.of(context).canResumeLocalProfile
                                      ? 'Continue local profile'
                                      : AppScope.of(context).isSignedOut &&
                                            AppScope.of(context).cloudEnabled
                                      ? 'Sign in'
                                      : 'Create my account'
                                : _page == 1
                                ? _ageLocked
                                      ? 'Guardian setup unavailable'
                                      : 'Continue with these choices'
                                : _page == 2
                                ? _signInExisting &&
                                          AppScope.of(context).cloudEnabled
                                      ? 'Sign in'
                                      : 'Continue to my profile'
                                : _page == 3
                                ? 'Set my schedule'
                                : _existingAccountVerified
                                ? 'Finish account setup'
                                : 'Start with demo data',
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppScope.of(context).cloudEnabled
                      ? 'Your data choices come before account setup.'
                      : AppScope.of(context).canResumeLocalProfile
                      ? 'Local mode. No password verification or Firebase sign-in.'
                      : 'Local mode. No Firebase account is created.',
                  style: TextStyle(color: TonyoColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _account(BuildContext context) => Form(
    key: _accountFormKey,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton.filledTonal(
            onPressed: _isSubmitting ? null : _previous,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _signInExisting ? 'Welcome back' : 'Create your account',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          AppScope.of(context).cloudEnabled
              ? _signInExisting
                    ? 'Sign in to restore your private Tonyo cloud data.'
                    : 'Your account securely syncs your Tonyo data through Firebase.'
              : 'Firebase values are not configured, so this build uses local demo storage.',
          style: TextStyle(color: TonyoColors.muted),
        ),
        if (AppScope.of(context).cloudEnabled) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      if (_signInExisting) {
                        setState(() {
                          _signInExisting = false;
                          _accountError = null;
                        });
                        await _pageController.animateToPage(
                          1,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                        );
                      } else {
                        setState(() {
                          _signInExisting = true;
                          _accountError = null;
                        });
                      }
                    },
              child: Text(
                _signInExisting
                    ? 'Create a new account instead'
                    : 'Already have an account? Sign in',
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        TextFormField(
          controller: _emailController,
          enabled: !_isSubmitting,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Enter your email';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('password-field'),
          controller: _passwordController,
          enabled: !_isSubmitting,
          obscureText: _obscurePassword,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: _signInExisting
              ? TextInputAction.done
              : TextInputAction.next,
          onFieldSubmitted: (_) {
            if (_signInExisting) _next();
          },
          autofillHints: [
            _signInExisting
                ? AutofillHints.password
                : AutofillHints.newPassword,
          ],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              key: const Key('password-visibility'),
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) {
            if (_signInExisting) {
              return (value ?? '').isEmpty ? 'Enter your password' : null;
            }
            if ((value ?? '').length < 8) {
              return 'Use at least 8 characters';
            }
            return null;
          },
        ),
        if (!_signInExisting) ...[
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('confirm-password-field'),
            controller: _confirmPasswordController,
            enabled: !_isSubmitting,
            obscureText: _obscureConfirmPassword,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_reset_rounded),
              suffixIcon: IconButton(
                key: const Key('confirm-password-visibility'),
                onPressed: _isSubmitting
                    ? null
                    : () => setState(
                        () =>
                            _obscureConfirmPassword = !_obscureConfirmPassword,
                      ),
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) => value != _passwordController.text
                ? 'Passwords do not match'
                : null,
          ),
        ],
        const SizedBox(height: 10),
        TonyoCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MetricIcon(
                icon: Icons.password_rounded,
                color: TonyoColors.mint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppScope.of(context).cloudEnabled
                      ? 'Firebase Authentication handles your password. Tonyo never writes passwords to Firestore or its local cache.'
                      : 'Your password is validated for this demo flow but is never saved.',
                  style: TextStyle(color: TonyoColors.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _privacyReview(BuildContext context) => ListView(
    key: const Key('onboarding-privacy-scroll'),
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton.filledTonal(
          tooltip: 'Back to welcome',
          onPressed: _isSubmitting ? null : _previous,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Before you begin',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Your choices come first. Account details come later.',
        style: TextStyle(color: TonyoColors.muted),
      ),
      if (AppScope.of(context).cloudEnabled) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('onboarding-privacy-existing-account'),
            onPressed: _isSubmitting ? null : _openExistingAccount,
            child: const Text('Already have an account? Sign in'),
          ),
        ),
      ],
      const SizedBox(height: 20),
      if (_ageLocked && _ageBand != null) ...[
        Text(
          'Selected age band: ${_ageBand!.label}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
      ],
      PrivacyChoicesForm(
        ageBand: _ageBand,
        region: _region,
        acknowledged: _acceptedPrivacy,
        enabled: !_isSubmitting && !_ageLocked,
        locked: _ageLocked,
        cloudEnabled: AppScope.of(context).cloudEnabled,
        onAgeChanged: (value) => setState(() {
          _ageBand = value;
          _acceptedPrivacy = false;
          _ageLocked = value != null && value != PrivacyAgeBand.adult;
        }),
        onRegionChanged: (value) => setState(() {
          _region = value;
          _acceptedPrivacy = false;
        }),
        onAcknowledged: (value) => setState(() => _acceptedPrivacy = value),
      ),
    ],
  );

  Widget _welcome(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 36, 28, 10),
    children: [
      const SizedBox(height: 12),
      Center(
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [TonyoColors.primary, TonyoColors.blue],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(color: Color(0x557567FF), blurRadius: 35),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 42,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Tonyo',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Make more informed choices about focus and recovery with estimates shaped by your daily signals.',
        textAlign: TextAlign.center,
        style: TextStyle(color: TonyoColors.muted, height: 1.45),
      ),
      if (AppScope.of(context).cloudEnabled &&
          !AppScope.of(context).canResumeLocalProfile) ...[
        const SizedBox(height: 12),
        TextButton(
          key: const Key('onboarding-welcome-sign-in'),
          onPressed: _isSubmitting ? null : _openExistingAccount,
          child: const Text('Already have an account? Sign in'),
        ),
      ],
      if (AppScope.of(context).canResumeLocalProfile) ...[
        const SizedBox(height: 18),
        const Text(
          'You are signed out. Continue your saved local profile on this device. Local mode does not verify a password or sign you into Firebase.',
          key: Key('onboarding-local-resume-notice'),
          textAlign: TextAlign.center,
          style: TextStyle(color: TonyoColors.muted, height: 1.45),
        ),
      ],
      const SizedBox(height: 28),
      TonyoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'Tomorrow’s energy forecast',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Illustrative demo',
                  style: TextStyle(
                    color: TonyoColors.mint,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ForecastChart(
              compact: true,
              height: 100,
              points: List.generate(
                10,
                (index) => ForecastPoint(
                  DateTime(2026, 1, 1, 7 + index),
                  52 + 20 * (index < 4 ? index / 4 : (9 - index) / 5),
                  8,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'LEARNS FROM YOUR SIGNALS',
        style: TextStyle(
          color: TonyoColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _SignalPill(Icons.bedtime_rounded, 'Sleep'),
          _SignalPill(Icons.menu_book_rounded, 'Study'),
          _SignalPill(Icons.fitness_center_rounded, 'Exercise'),
          _SignalPill(Icons.smartphone_rounded, 'Screen'),
          _SignalPill(Icons.bolt_rounded, 'Reaction'),
          _SignalPill(Icons.monitor_heart_rounded, 'Wearable'),
        ],
      ),
    ],
  );

  Widget _profile(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 38, 24, 12),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton.filledTonal(
          onPressed: _isSubmitting || _existingAccountVerified
              ? null
              : _previous,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      const SizedBox(height: 20),
      Text('Make it yours', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      const Text(
        'These details shape recommendations. You can change them later.',
        style: TextStyle(color: TonyoColors.muted),
      ),
      const SizedBox(height: 28),
      TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'First name'),
      ),
      const SizedBox(height: 14),
      Text(
        'Age band: ${AppScope.of(context).privacyConsent?.ageBand.label ?? _ageBand?.label ?? 'Review required'}',
        style: const TextStyle(color: TonyoColors.muted),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: _role,
        decoration: const InputDecoration(labelText: 'I am a…'),
        items: ['Student', 'Athlete', 'Student athlete']
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: (value) => setState(() => _role = value!),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: _goal,
        decoration: const InputDecoration(labelText: 'Primary goal'),
        items:
            ['Improve focus', 'Improve recovery', 'Balance focus and training']
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
        onChanged: (value) => setState(() {
          _goal = value!;
          _coachPriority = coachPriorityFromGoal(value);
        }),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<CoachPriority>(
        key: const Key('onboarding-coach-priority'),
        initialValue: _coachPriority,
        decoration: const InputDecoration(labelText: 'AI Coach priority'),
        items: CoachPriority.values
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(value.label)),
            )
            .toList(),
        onChanged: (value) => setState(() => _coachPriority = value!),
      ),
      const SizedBox(height: 20),
      const TonyoCard(
        child: Row(
          children: [
            MetricIcon(icon: Icons.shield_outlined, color: TonyoColors.mint),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Tonyo is a wellness tool, not medical advice. It never diagnoses fatigue or burnout.',
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _schedule(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 38, 24, 12),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton.filledTonal(
          onPressed: _isSubmitting ? null : _previous,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'Your usual rhythm',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Tonyo uses your routine to build an initial circadian forecast.',
        style: TextStyle(color: TonyoColors.muted),
      ),
      const SizedBox(height: 32),
      TonyoCard(
        child: Column(
          children: [
            _SliderSetting(
              icon: Icons.wb_sunny_outlined,
              title: 'Wake time',
              value: _wake,
              label: _timeLabel(_wake),
              min: 5,
              max: 11,
              onChanged: (value) => setState(() => _wake = value),
            ),
            const Divider(height: 30, color: TonyoColors.border),
            _SliderSetting(
              icon: Icons.bedtime_outlined,
              title: 'Bedtime',
              value: _bed,
              label: _timeLabel(_bed),
              min: 20,
              max: 25,
              onChanged: (value) => setState(() => _bed = value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const TonyoCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetricIcon(
              icon: Icons.auto_awesome_rounded,
              color: TonyoColors.primary,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Start with a useful demo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Fixture signals make every dashboard immediately explorable. Replace them with your entries whenever you’re ready.',
                    style: TextStyle(color: TonyoColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _next() async {
    if (_isSubmitting) return;
    final controller = AppScope.of(context);
    if (controller.canResumeLocalProfile) {
      // Resume the saved device profile without passing through setup, which
      // would replace its profile and seeded data. Local mode is not auth.
      setState(() {
        _isSubmitting = true;
        _accountError = null;
      });
      try {
        await controller.resumeLocalProfile();
      } on Object {
        if (mounted) {
          setState(() {
            _accountError =
                'Could not open your local profile. Your saved data is kept. Please try again.';
          });
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }
    if (_page == 0 && controller.isSignedOut && controller.cloudEnabled) {
      await _openExistingAccount();
      return;
    }
    if (_page == 1) {
      if (_ageBand == null || _region == null || !_acceptedPrivacy) {
        setState(
          () => _accountError = _ageLocked
              ? 'New account setup is paused until verified guardian setup is available. You can still sign in to an existing account.'
              : 'Choose your age band and region, then read and acknowledge the data-use notice.',
        );
        return;
      }
      if (_ageBand != PrivacyAgeBand.adult) {
        setState(
          () => _accountError =
              'New account setup is paused until verified guardian setup is available.',
        );
        return;
      }
      setState(() {
        _isSubmitting = true;
        _accountError = null;
      });
      try {
        await controller.acceptPrivacy(
          ageBand: _ageBand!,
          region: _region!,
          acknowledged: _acceptedPrivacy,
        );
      } on Object {
        if (mounted) {
          setState(
            () => _accountError =
                controller.privacyOperationError ??
                'Your privacy choices could not be saved. Please try again.',
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      if (!mounted) return;
    }
    if (_page == 2) {
      final valid = _accountFormKey.currentState?.validate() ?? false;
      if (!valid) return;
      if (_signInExisting && controller.cloudEnabled) {
        // Stay on the account form until Firebase verifies these credentials.
        // Existing users restore their profile rather than redoing onboarding.
        FocusScope.of(context).unfocus();
        setState(() {
          _isSubmitting = true;
          _accountError = null;
        });
        try {
          await controller.signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
          if (!mounted || controller.onboardingComplete) return;
          if (controller.cloudSyncError != null) {
            setState(() {
              _accountError =
                  'Your password was verified, but your saved data could not be loaded. Please try signing in again.';
            });
            return;
          }
          _existingAccountVerified = true;
          _passwordController.clear();
          _confirmPasswordController.clear();
          await _pageController.nextPage(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        } on Object catch (error) {
          if (mounted) {
            setState(() {
              _accountError =
                  error is! FirebaseAuthException &&
                      controller.isCloudAuthenticated &&
                      controller.cloudSyncError != null
                  ? 'Your password was verified, but your saved data could not be loaded. Please try signing in again.'
                  : accountErrorMessage(error);
            });
          }
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
        return;
      }
    }
    if (_page < 4) {
      setState(() {
        _isSubmitting = true;
        _accountError = null;
      });
      try {
        await _pageController.nextPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }
    setState(() {
      _isSubmitting = true;
      _accountError = null;
    });
    final name = _nameController.text.trim();
    try {
      final profile = UserProfile(
        name: name.isEmpty ? 'Your profile' : name,
        ageRange:
            controller.privacyConsent?.ageBand.label ??
            _ageBand?.label ??
            'Not provided',
        role: _role,
        goal: _goal,
        coachPriority: _coachPriority,
        wakeHour: _wake,
        bedHour: _bed,
      );
      if (_existingAccountVerified) {
        await controller.completeAuthenticatedOnboarding(profile);
      } else {
        await controller.completeOnboarding(
          profile,
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      _passwordController.clear();
      _confirmPasswordController.clear();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _accountError = accountErrorMessage(error, signingIn: false);
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _previous() async {
    if (_isSubmitting ||
        _page == 0 ||
        (_existingAccountVerified && _page == 3)) {
      return;
    }
    setState(() => _accountError = null);
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openExistingAccount() async {
    if (_isSubmitting) return;
    setState(() {
      _signInExisting = true;
      _accountError = null;
    });
    await _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  String _timeLabel(double value) {
    var hour = value.floor();
    final minute = ((value - hour) * 60).round();
    hour %= 24;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: TonyoColors.surface,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: TonyoColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: TonyoColors.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.icon,
    required this.title,
    required this.value,
    required this.label,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final double value;
  final String label;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Icon(icon, color: TonyoColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: TonyoColors.mint,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: ((max - min) * 2).round(),
        onChanged: onChanged,
      ),
    ],
  );
}
