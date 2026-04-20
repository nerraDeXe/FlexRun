import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/material.dart';

import 'package:fake_strava/auth/pages/login_page.dart';
import 'package:fake_strava/auth/pages/verify_email_page.dart';
import 'package:fake_strava/dashboard/dashboard_shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.bootstrapError});

  final Object? bootstrapError;

  @override
  Widget build(BuildContext context) {
    if (bootstrapError != null) {
      return _AuthSetupIssuePage(
        message: 'Firebase initialization failed: $bootstrapError',
      );
    }

    if (Firebase.apps.isEmpty) {
      return const _AuthSetupIssuePage(
        message:
            'Firebase is not initialized on this platform.\n\nEnable Firebase for this target and restart the app.',
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginPage();
        }

        if (!user.emailVerified) {
          return VerifyEmailPage(user: user);
        }

        final displayName =
            (user.displayName != null && user.displayName!.trim().isNotEmpty)
            ? user.displayName!.trim()
            : (user.email ?? 'Runner');

        return TrackingDashboardShell(
          displayName: displayName,
          onLogout: () => FirebaseAuth.instance.signOut(),
        );
      },
    );
  }
}

class _AuthSetupIssuePage extends StatelessWidget {
  const _AuthSetupIssuePage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

