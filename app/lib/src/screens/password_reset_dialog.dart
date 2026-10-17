import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../account_error.dart';
import '../app_controller.dart';
import '../password_reset.dart';
import '../theme.dart';

enum _ResetStep { request, code, newPassword }

/// Signed-out password recovery: request an email, paste its link or code,
/// then choose a new password. Pops with the reset account's email.
class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({
    super.key,
    required this.controller,
    this.initialEmail,
  });

  final AppController controller;
  final String? initialEmail;

  static Future<String?> show(
    BuildContext context, {
    required AppController controller,
    String? initialEmail,
  }) => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        PasswordResetDialog(controller: controller, initialEmail: initialEmail),
  );

  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _codeInput = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  _ResetStep _step = _ResetStep.request;
  bool _isSubmitting = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _sentToEmail;
  String? _code;
  String? _resetEmail;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _codeInput.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // Email clients often wrap long links across lines.
  String? get _parsedCode => parsePasswordResetCode(
    _codeInput.text.replaceAll(RegExp(r'[\r\n]+'), ''),
  );

  bool _beginSubmit() {
    if (_isSubmitting || !_formKey.currentState!.validate()) return false;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    return true;
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _error = passwordResetErrorMessage(error);
    });
  }

  Future<void> _sendResetEmail() async {
    if (!_beginSubmit()) return;
    final email = _email.text.trim();
    try {
      await widget.controller.sendPasswordReset(email: email);
    } on Object catch (error) {
      // Never reveal whether an account exists for this email.
      if (error is! FirebaseAuthException || error.code != 'user-not-found') {
        _fail(error);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _sentToEmail = email;
      _step = _ResetStep.code;
    });
  }

  Future<void> _verifyCode() async {
    if (!_beginSubmit()) return;
    final code = _parsedCode!;
    try {
      final email = await widget.controller.verifyPasswordResetCode(code);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _code = code;
        _resetEmail = email;
        _step = _ResetStep.newPassword;
      });
    } on Object catch (error) {
      _fail(error);
    }
  }

  Future<void> _confirmReset() async {
    if (!_beginSubmit()) return;
    try {
      await widget.controller.confirmPasswordReset(
        code: _code!,
        newPassword: _newPassword.text,
      );
      if (mounted) Navigator.of(context).pop(_resetEmail);
    } on Object catch (error) {
      _fail(error);
    }
  }

  void _goTo(_ResetStep step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
      if (step == _ResetStep.request) {
        _sentToEmail = null;
        _code = null;
        _resetEmail = null;
        _codeInput.clear();
        _newPassword.clear();
        _confirmPassword.clear();
      }
    });
  }

  void _submit() => switch (_step) {
    _ResetStep.request => _sendResetEmail(),
    _ResetStep.code => _verifyCode(),
    _ResetStep.newPassword => _confirmReset(),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isSubmitting,
    child: AlertDialog(
      title: Text(context.tr('Reset your password')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...switch (_step) {
                  _ResetStep.request => _requestFields(context),
                  _ResetStep.code => _codeFields(context),
                  _ResetStep.newPassword => _newPasswordFields(context),
                },
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(_error!),
                      key: const Key('password-reset-error'),
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
          key: const Key('password-reset-cancel'),
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          key: Key(switch (_step) {
            _ResetStep.request => 'password-reset-send',
            _ResetStep.code => 'password-reset-verify',
            _ResetStep.newPassword => 'password-reset-submit',
          }),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(context.tr('Please wait…')),
                  ],
                )
              : Text(
                  context.tr(switch (_step) {
                    _ResetStep.request => 'Send reset email',
                    _ResetStep.code => 'Continue',
                    _ResetStep.newPassword => 'Reset password',
                  }),
                ),
        ),
      ],
    ),
  );

  Widget _muted(BuildContext context, String text, {Key? key}) => Text(
    text,
    key: key,
    style: TextStyle(color: TonyoPalette.of(context).muted, fontSize: 12),
  );

  Widget _requestNewEmailButton(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      key: const Key('password-reset-request-new'),
      onPressed: _isSubmitting ? null : () => _goTo(_ResetStep.request),
      child: Text(context.tr('Request a new email')),
    ),
  );

  List<Widget> _requestFields(BuildContext context) => [
    _muted(
      context,
      context.tr(
        'Enter your account email. We will send you a link to reset your password.',
      ),
    ),
    const SizedBox(height: 14),
    TextFormField(
      key: const Key('password-reset-email'),
      controller: _email,
      enabled: !_isSubmitting,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.username],
      autocorrect: false,
      decoration: InputDecoration(labelText: context.tr('Email')),
      validator: (value) {
        final email = value?.trim() ?? '';
        if (email.isEmpty) return context.tr('Enter your email.');
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
          return context.tr('Enter a valid email address.');
        }
        return null;
      },
      onFieldSubmitted: (_) => _sendResetEmail(),
    ),
    const SizedBox(height: 4),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const Key('password-reset-have-code'),
        onPressed: _isSubmitting ? null : () => _goTo(_ResetStep.code),
        child: Text(context.tr('I already have a code')),
      ),
    ),
  ];

  List<Widget> _codeFields(BuildContext context) => [
    if (_sentToEmail != null) ...[
      Semantics(
        liveRegion: true,
        child: Text(
          context.tr(
            'If an account exists for {email}, we sent a password reset email. Press and hold the link in the email, choose Copy, and paste it here.',
            args: {'email': _sentToEmail},
          ),
          key: const Key('password-reset-sent'),
        ),
      ),
      const SizedBox(height: 14),
    ],
    TextFormField(
      key: const Key('password-reset-code'),
      controller: _codeInput,
      enabled: !_isSubmitting,
      keyboardType: TextInputType.multiline,
      minLines: 1,
      maxLines: 4,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: context.tr('Reset link or code'),
        helperText: context.tr('You can paste the whole link from the email.'),
        helperMaxLines: 2,
      ),
      validator: (_) => _parsedCode == null
          ? context.tr('Paste the reset link or code from the email.')
          : null,
    ),
    const SizedBox(height: 4),
    _requestNewEmailButton(context),
  ];

  List<Widget> _newPasswordFields(BuildContext context) => [
    _muted(
      context,
      context.tr(
        'Choose a new password for {email}.',
        args: {'email': _resetEmail},
      ),
      key: const Key('password-reset-account-email'),
    ),
    const SizedBox(height: 14),
    TextFormField(
      key: const Key('password-reset-new-password'),
      controller: _newPassword,
      enabled: !_isSubmitting,
      obscureText: _obscureNewPassword,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: context.tr('New password'),
        suffixIcon: IconButton(
          key: const Key('password-reset-new-password-visibility'),
          tooltip: context.tr(
            _obscureNewPassword ? 'Show password' : 'Hide password',
          ),
          onPressed: _isSubmitting
              ? null
              : () =>
                    setState(() => _obscureNewPassword = !_obscureNewPassword),
          icon: Icon(
            _obscureNewPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) {
        final message = validateNewPassword(value);
        return message == null ? null : context.tr(message);
      },
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('password-reset-confirm-password'),
      controller: _confirmPassword,
      enabled: !_isSubmitting,
      obscureText: _obscureConfirmPassword,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      decoration: InputDecoration(
        labelText: context.tr('Confirm new password'),
        suffixIcon: IconButton(
          key: const Key('password-reset-confirm-password-visibility'),
          tooltip: context.tr(
            _obscureConfirmPassword ? 'Show password' : 'Hide password',
          ),
          onPressed: _isSubmitting
              ? null
              : () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
          icon: Icon(
            _obscureConfirmPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) => value != _newPassword.text
          ? context.tr('Passwords do not match')
          : null,
      onFieldSubmitted: (_) => _confirmReset(),
    ),
    const SizedBox(height: 4),
    _requestNewEmailButton(context),
  ];
}
