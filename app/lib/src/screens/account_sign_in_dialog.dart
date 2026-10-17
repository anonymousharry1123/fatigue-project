import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../account_error.dart';
import '../app_controller.dart';
import '../theme.dart';
import 'password_reset_dialog.dart';

/// Keeps account entry visible until Firebase has accepted the credentials.
class AccountSignInDialog extends StatefulWidget {
  const AccountSignInDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountSignInDialog> createState() => _AccountSignInDialogState();
}

class _AccountSignInDialogState extends State<AccountSignInDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(
    text: widget.controller.accountEmail,
  );
  final _password = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _forgotPassword() async {
    if (_isSubmitting) return;
    final initialEmail = _email.text.trim();
    final email = await PasswordResetDialog.show(
      context,
      controller: widget.controller,
      initialEmail: initialEmail.isEmpty ? null : initialEmail,
    );
    if (!mounted || email == null) return;
    setState(() {
      _email.text = email;
      _password.clear();
      _error = null;
      _info = 'Password updated. Sign in with your new password.';
    });
  }

  Future<void> _signIn() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.controller.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = accountErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isSubmitting,
    child: AlertDialog(
      title: Text(context.tr('Sign in to Tonyo')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr(
                    'Your existing local data is migrated only if this cloud account has no Tonyo data yet.',
                  ),
                  style: TextStyle(
                    color: TonyoPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('profile-sign-in-email'),
                  controller: _email,
                  enabled: !_isSubmitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  decoration: InputDecoration(labelText: context.tr('Email')),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return context.tr('Enter your email.');
                    if (!RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(email)) {
                      return context.tr('Enter a valid email address.');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('profile-sign-in-password'),
                  controller: _password,
                  enabled: !_isSubmitting,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: context.tr('Password'),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? context.tr('Enter your password.')
                      : null,
                  onFieldSubmitted: (_) => _signIn(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('profile-sign-in-forgot-password'),
                    onPressed: _isSubmitting ? null : _forgotPassword,
                    child: Text(context.tr('Forgot password?')),
                  ),
                ),
                if (_info != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(_info!),
                      key: const Key('profile-sign-in-info'),
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(_error!),
                      key: const Key('profile-sign-in-error'),
                      style: TextStyle(color: TonyoPalette.of(context).error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('profile-sign-in-cancel'),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: const Key('profile-sign-in-submit'),
          onPressed: _isSubmitting ? null : _signIn,
          child: _isSubmitting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(context.tr('Signing in…')),
                  ],
                )
              : Text(context.tr('Sign in')),
        ),
      ],
    ),
  );
}
