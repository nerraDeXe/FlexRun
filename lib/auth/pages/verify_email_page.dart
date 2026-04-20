import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/utils.dart';



class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.user});

  final User user;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _isSending = false;
  bool _isRefreshing = false;
  int _resendCooldownSeconds = 0;
  Timer? _resendCooldownTimer;

  @override
  void dispose() {
    _resendCooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 45]) {
    _resendCooldownTimer?.cancel();
    setState(() => _resendCooldownSeconds = seconds);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendCooldownSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _resendCooldownSeconds = 0);
        }
        return;
      }
      setState(() => _resendCooldownSeconds -= 1);
    });
  }

  Future<void> _resendVerification() async {
    if (_resendCooldownSeconds > 0) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.user.sendEmailVerification();
      _startResendCooldown();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification email sent.')));
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeAuthError(error))));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _refreshUser() async {
    setState(() => _isRefreshing = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (!mounted) {
        return;
      }
      if (FirebaseAuth.instance.currentUser?.emailVerified != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email is not verified yet.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: kBrandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'ACTION REQUIRED',
                          style: TextStyle(
                            color: kBrandOrange,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Verify your email',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A verification link was sent to ${widget.user.email ?? 'your email'}.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isSending || _resendCooldownSeconds > 0
                            ? null
                            : _resendVerification,
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: Text(
                          _isSending
                              ? 'Sending...'
                              : (_resendCooldownSeconds > 0
                                    ? 'Resend in ${_resendCooldownSeconds}s'
                                    : 'Resend verification email'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isRefreshing ? null : _refreshUser,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _isRefreshing ? 'Checking...' : 'I have verified',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        child: const Text('Use a different account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

