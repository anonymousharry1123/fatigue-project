import 'package:flutter/material.dart';

import '../app.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _accountFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController(text: 'Maya');
  int _page = 0;
  bool _acceptedPrivacy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _age = '16–18';
  String _role = 'Student athlete';
  String _goal = 'Balance focus and training';
  double _wake = 7;
  double _bed = 23;

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
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
                  height: 54,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      backgroundColor: TonyoColors.primary,
                    ),
                    child: Text(
                      _page == 0
                          ? 'Create my account'
                          : _page == 1
                          ? 'Continue to my profile'
                          : _page == 2
                          ? 'Set my schedule'
                          : 'Start with demo data',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Private by design. Your data stays on this device.',
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
            onPressed: _previous,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Create your account',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Start with a local account. Cloud sign-in and syncing will be added in a later release.',
          style: TextStyle(color: TonyoColors.muted),
        ),
        const SizedBox(height: 28),
        TextFormField(
          controller: _emailController,
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
          obscureText: _obscurePassword,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              key: const Key('password-visibility'),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) {
            if ((value ?? '').length < 8) {
              return 'Use at least 8 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const Key('confirm-password-field'),
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_reset_rounded),
            suffixIcon: IconButton(
              key: const Key('confirm-password-visibility'),
              onPressed: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
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
        const SizedBox(height: 14),
        CheckboxListTile(
          value: _acceptedPrivacy,
          onChanged: (value) =>
              setState(() => _acceptedPrivacy = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'I understand this preview stores my account email and app data locally on this device.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        const TonyoCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetricIcon(icon: Icons.password_rounded, color: TonyoColors.mint),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your password is validated for this setup flow but is never saved. Authentication arrives with a secure account service later.',
                  style: TextStyle(color: TonyoColors.muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
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
        'Your personal AI that forecasts fatigue before it hits — and tells you exactly what to do about it.',
        textAlign: TextAlign.center,
        style: TextStyle(color: TonyoColors.muted, height: 1.45),
      ),
      const SizedBox(height: 28),
      TonyoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tomorrow’s energy forecast',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '92% confident',
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
          onPressed: _previous,
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
      DropdownButtonFormField<String>(
        initialValue: _age,
        decoration: const InputDecoration(labelText: 'Age range'),
        items: ['13–15', '16–18', '18+']
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: (value) => setState(() => _age = value!),
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
        onChanged: (value) => setState(() => _goal = value!),
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
          onPressed: _previous,
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
    if (_page == 1) {
      final valid = _accountFormKey.currentState?.validate() ?? false;
      if (!valid || !_acceptedPrivacy) {
        if (!_acceptedPrivacy) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Confirm the local-data notice to continue.'),
            ),
          );
        }
        return;
      }
    }
    if (_page < 3) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    final name = _nameController.text.trim();
    await AppScope.of(context).completeOnboarding(
      UserProfile(
        name: name.isEmpty ? 'Maya' : name,
        ageRange: _age,
        role: _role,
        goal: _goal,
        wakeHour: _wake,
        bedHour: _bed,
      ),
      email: _emailController.text,
    );
  }

  Future<void> _previous() async {
    if (_page == 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 240),
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
