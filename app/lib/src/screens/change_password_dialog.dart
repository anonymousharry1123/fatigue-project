import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../account_error.dart';
import '../app_controller.dart';
import '../password_reset.dart';
import '../theme.dart';

/// Requires the current password so Firebase can reauthenticate first.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _isSubmitting = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.controller.changePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = passwordResetErrorMessage(error, changingPassword: true);
      });
    }
  }

  Widget _passwordField({
    required Key key,
    required Key visibilityKey,
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String autofillHint,
    required TextInputAction action,
    required FormFieldValidator<String> validator,
    ValueChanged<String>? onSubmitted,
  }) => TextFormField(
    key: key,
    controller: controller,
    enabled: !_isSubmitting,
    obscureText: obscure,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: action,
    autofillHints: [autofillHint],
    decoration: InputDecoration(
      labelText: context.tr(label),
      suffixIcon: IconButton(
        key: visibilityKey,
        tooltip: context.tr(obscure ? 'Show password' : 'Hide password'),
        onPressed: _isSubmitting ? null : onToggle,
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: validator,
    onFieldSubmitted: onSubmitted,
  );

  @override
  Widget build(BuildContext context) {
    final email = widget.controller.accountEmail;
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(context.tr('Change password')),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (email != null) ...[
                    Text(
                      email,
                      key: const Key('change-password-email'),
                      style: TextStyle(
                        color: TonyoPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _passwordField(
                    key: const Key('change-password-current'),
                    visibilityKey: const Key(
                      'change-password-current-visibility',
                    ),
                    controller: _currentPassword,
                    label: 'Current password',
                    obscure: _obscureCurrentPassword,
                    onToggle: () => setState(
                      () => _obscureCurrentPassword = !_obscureCurrentPassword,
                    ),
                    autofillHint: AutofillHints.password,
                    action: TextInputAction.next,
                    validator: (value) => value == null || value.isEmpty
                        ? context.tr('Enter your current password.')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _passwordField(
                    key: const Key('change-password-new'),
                    visibilityKey: const Key('change-password-new-visibility'),
                    controller: _newPassword,
                    label: 'New password',
                    obscure: _obscureNewPassword,
                    onToggle: () => setState(
                      () => _obscureNewPassword = !_obscureNewPassword,
                    ),
                    autofillHint: AutofillHints.newPassword,
                    action: TextInputAction.next,
                    validator: (value) {
                      final problem = validateNewPassword(value);
                      if (problem != null) return context.tr(problem);
                      if (value == _currentPassword.text) {
                        return context.tr(
                          'Choose a password different from your current one.',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _passwordField(
                    key: const Key('change-password-confirm'),
                    visibilityKey: const Key(
                      'change-password-confirm-visibility',
                    ),
                    controller: _confirmPassword,
                    label: 'Confirm new password',
                    obscure: _obscureConfirmPassword,
                    onToggle: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                    autofillHint: AutofillHints.newPassword,
                    action: TextInputAction.done,
                    validator: (value) => value != _newPassword.text
                        ? context.tr('Passwords do not match')
                        : null,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        context.tr(_error!),
                        key: const Key('change-password-error'),
                        style: TextStyle(
                          color: TonyoPalette.of(context).error,
                        ),
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
            key: const Key('change-password-cancel'),
            onPressed: _isSubmitting
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            key: const Key('change-password-submit'),
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
                      Text(context.tr('Updating…')),
                    ],
                  )
                : Text(context.tr('Update password')),
          ),
        ],
      ),
    );
  }
}
