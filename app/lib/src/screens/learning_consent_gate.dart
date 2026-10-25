import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/translated_text.dart';

/// Offered after normal account/privacy setup, before the first eligible shell.
class LearningConsentGate extends StatefulWidget {
  const LearningConsentGate({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppController controller;
  final Widget child;

  @override
  State<LearningConsentGate> createState() => _LearningConsentGateState();
}

class _LearningConsentGateState extends State<LearningConsentGate> {
  bool _checking = false;
  bool _checked = false;
  bool _offer = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant LearningConsentGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _check();
  }

  Future<void> _check() async {
    if (_checking || _checked || !widget.controller.learningSetupAvailable) {
      return;
    }
    _checking = true;
    final controller = widget.controller;
    final revision = controller.sessionRevision;
    final owner = controller.cloudUid;
    try {
      final offer = await controller.shouldOfferLearningSetup();
      if (!_current(controller, revision, owner)) return;
      setState(() {
        _offer = offer;
        _checked = true;
      });
    } on Object {
      if (!_current(controller, revision, owner)) return;
      setState(() {
        _checked = true;
        _error =
            'Could not load your learning choice. Your settings have not changed.';
      });
    } finally {
      _checking = false;
    }
  }

  bool _current(AppController controller, int revision, String? owner) =>
      mounted &&
      identical(controller, widget.controller) &&
      controller.sessionRevision == revision &&
      controller.cloudUid == owner &&
      controller.learningSetupAvailable;

  Future<void> _choose(bool enable) async {
    if (_working) return;
    final controller = widget.controller;
    final revision = controller.sessionRevision;
    final owner = controller.cloudUid;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await controller.completeLearningSetup(enable: enable);
      if (!_current(controller, revision, owner)) return;
      setState(() => _offer = false);
    } on Object {
      if (!mounted || !_current(controller, revision, owner)) return;
      if (!enable) {
        // Optional collection must not block ordinary use when this device
        // cannot persist the prompt receipt. No feature is enabled on this path.
        setState(() => _offer = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: TranslatedText(
              'Your settings are unchanged. Your choice could not be saved, so you may be asked again.',
            ),
          ),
        );
        return;
      }
      setState(
        () => _error =
            'Setup did not finish. Check the settings below, then retry or keep your current settings.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.learningSetupAvailable || (_checked && !_offer)) {
      return widget.child;
    }
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: !_checked
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 24),
                    TranslatedText(
                      'Enable optional learning?',
                      key: const Key('learning-setup-prompt'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const TranslatedText(
                      'With your permission, Tonyo can turn on both settings below. This is optional and does not start model training.',
                    ),
                    const SizedBox(height: 20),
                    _SettingExplanation(
                      title: 'Local study history',
                      detail:
                          'Keep future sleep and check-in revisions on this iPhone, including save times and edits. This history is not uploaded.',
                      enabled: controller.ai1CaptureEnabled,
                    ),
                    const SizedBox(height: 12),
                    _SettingExplanation(
                      title: 'Outcome learning',
                      detail: controller.isCloudAuthenticated
                          ? 'Save eligible future outcome records to your private account for model preparation. Model training is a separate action, and model weights stay on this device.'
                          : 'Save eligible future outcome records on this device for model preparation. Model training is a separate action.',
                      enabled: controller.outcomeConsent,
                    ),
                    const SizedBox(height: 16),
                    const TranslatedText(
                      'You can turn either setting off in Profile → Privacy center. Turning off local study history clears that history; your ordinary logs remain.',
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: TranslatedText(
                          error,
                          key: const Key('learning-setup-error'),
                          style: TextStyle(
                            color: TonyoPalette.of(context).error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('learning-setup-allow'),
                      onPressed: _working ? null : () => _choose(true),
                      child: TranslatedText(
                        _working ? 'Saving…' : 'Allow and enable both',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('learning-setup-decline'),
                      onPressed: _working ? null : () => _choose(false),
                      child: const TranslatedText('Keep current settings'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SettingExplanation extends StatelessWidget {
  const _SettingExplanation({
    required this.title,
    required this.detail,
    required this.enabled,
  });
  final String title;
  final String detail;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TonyoCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TranslatedText(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TranslatedText(detail),
        const SizedBox(height: 8),
        Text(
          context.tr(enabled ? 'Currently on' : 'Currently off'),
          style: TextStyle(color: TonyoPalette.of(context).muted),
        ),
      ],
    ),
  );
}
