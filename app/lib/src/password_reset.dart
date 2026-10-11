const minimumPasswordLength = 8;

/// Extracts a reset code from a pasted code, Firebase action link, or a link
/// that wraps one in its `link` or `continueUrl` parameter.
String? parsePasswordResetCode(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || RegExp(r'\s').hasMatch(trimmed)) return null;
  if (!RegExp(r'[/?&=#:]').hasMatch(trimmed)) return trimmed;
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  return uri == null ? null : _codeFromUri(uri, depth: 0);
}

String? _codeFromUri(Uri uri, {required int depth}) {
  final Map<String, String> params;
  try {
    params = uri.queryParameters;
  } on FormatException {
    return null;
  }
  final mode = params['mode'];
  if (mode != null && mode != 'resetPassword') return null;
  final code = params['oobCode']?.trim();
  if (code != null && code.isNotEmpty) return code;
  if (depth >= 2) return null;
  for (final key in const ['link', 'continueUrl']) {
    final nested = Uri.tryParse(params[key]?.trim() ?? '');
    if (nested != null && nested.hasScheme) {
      final nestedCode = _codeFromUri(nested, depth: depth + 1);
      if (nestedCode != null) return nestedCode;
    }
  }
  return null;
}

/// Returns English form copy for `context.tr`, or null when [value] is valid.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Enter a new password.';
  if (password.length < minimumPasswordLength) {
    return 'Use at least 8 characters';
  }
  return null;
}
