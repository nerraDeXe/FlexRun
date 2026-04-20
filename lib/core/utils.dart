import 'package:firebase_auth/firebase_auth.dart';

String humanizeAuthError(Object error) {
  if (error is! FirebaseAuthException) {
    return error.toString();
  }
  switch (error.code) {
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is incorrect.';
    case 'email-already-in-use':
      return 'This email is already registered. Try another one.';
    case 'weak-password':
      return 'Password is too weak. Use at least 6 characters.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again shortly.';
    case 'requires-recent-login':
      return 'Please re-authenticate with your current password and try again.';
    case 'operation-not-allowed':
      return 'Email/password sign-in is disabled in Firebase Console.';
    default:
      return error.message ?? 'Authentication failed.';
  }
}

String formatSessionDuration(
  DateTime? startedAt,
  DateTime? endedAt, {
  int? durationSeconds,
}) {
  if (durationSeconds != null) {
    final Duration duration = Duration(seconds: durationSeconds);
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString()}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
  if (startedAt != null && endedAt != null) {
    final Duration duration = endedAt.difference(startedAt);
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString()}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }
  return '0:00';
}