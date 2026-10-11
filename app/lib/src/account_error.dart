import 'package:firebase_auth/firebase_auth.dart';

/// Safe form copy; never display raw SDK errors or submitted credentials.
String accountErrorMessage(Object error, {bool signingIn = true}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return 'The email or password is incorrect. Please try again.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'network-request-failed':
        return 'Unable to connect. Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a little before trying again.';
      case 'user-disabled':
        return 'This account is disabled. Please contact support.';
      case 'email-already-in-use':
        return 'An account already exists for this email. Choose “Already have an account? Sign in”.';
      case 'weak-password':
        return 'Choose a stronger password and try again.';
      case 'operation-not-allowed':
      case 'invalid-api-key':
      case 'app-not-authorized':
        return 'Account access is unavailable in this build. Please check the Firebase configuration.';
    }
  }
  return signingIn
      ? 'Sign-in could not be completed. Please try again.'
      : 'Account setup could not be completed. Please try again.';
}

/// Reset requests must always show neutral "sent" copy instead of this, so
/// `user-not-found` never reveals whether an account exists.
String passwordResetErrorMessage(
  Object error, {
  bool changingPassword = false,
}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'expired-action-code':
      case 'invalid-action-code':
      case 'user-not-found':
        return 'This reset code is invalid or has expired. Request a new email.';
      case 'requires-recent-login':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'invalid-login-credentials':
        return 'Current password is incorrect.';
      case 'weak-password':
      case 'network-request-failed':
      case 'too-many-requests':
      case 'invalid-email':
      case 'user-disabled':
      case 'operation-not-allowed':
      case 'invalid-api-key':
      case 'app-not-authorized':
        return accountErrorMessage(error);
    }
  }
  return changingPassword
      ? 'The password could not be changed. Please try again.'
      : 'The password could not be reset. Please try again.';
}
