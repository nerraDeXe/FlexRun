import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'tracking/models/tracking_snapshot.dart';
import 'tracking/services/tracking_background_service.dart';

const Color _kBrandOrange = Color(0xFFFC4C02);
const Color _kBrandBlack = Color(0xFF121212);
const Color _kSurface = Color(0xFFF4F5F7);
const Color _kSurfaceCard = Color(0xFFFFFFFF);

String _humanizeAuthError(Object error) {
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? bootstrapError;
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      await TrackingBackgroundService().initialize();
    } catch (error) {
      bootstrapError = error;
    }
  }
  runApp(FakeStravaApp(bootstrapError: bootstrapError));
}

class FakeStravaApp extends StatelessWidget {
  const FakeStravaApp({super.key, this.bootstrapError});

  final Object? bootstrapError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fake Strava',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kBrandOrange,
          primary: _kBrandOrange,
          surface: _kSurface,
        ),
        scaffoldBackgroundColor: _kSurface,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _kBrandBlack,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: _kSurfaceCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: _kBrandOrange, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _kBrandOrange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: AuthGate(bootstrapError: bootstrapError),
    );
  }
}

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

class TrackingDashboardShell extends StatefulWidget {
  const TrackingDashboardShell({
    super.key,
    required this.displayName,
    required this.onLogout,
  });

  final String displayName;
  final Future<void> Function() onLogout;

  @override
  State<TrackingDashboardShell> createState() => _TrackingDashboardShellState();
}

class _TrackingDashboardShellState extends State<TrackingDashboardShell> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          TrackingHomePage(displayName: widget.displayName),
          ProgressPage(displayName: widget.displayName),
          ProfilePage(
            displayName: widget.displayName,
            onLogout: widget.onLogout,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x2A000000),
              blurRadius: 20,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBar(
          height: 72,
          backgroundColor: const Color(0xFF191919),
          indicatorColor: _kBrandOrange.withValues(alpha: 0.20),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              );
            }
            return const TextStyle(color: Colors.white70);
          }),
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedTabIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.directions_run_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.directions_run, color: _kBrandOrange),
              label: 'Track',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.insights, color: _kBrandOrange),
              label: 'Progress',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: Colors.white70),
              selectedIcon: Icon(Icons.person, color: _kBrandOrange),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key, required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) {
      return const Center(child: Text('Firebase is not ready yet.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('tracking_sessions')
          .orderBy('startedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Unable to load progress.\n\n${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final sessions = snapshot.data!.docs;
        final now = DateTime.now().toUtc();
        final weekStart = now.subtract(const Duration(days: 7));
        var weekDistanceMeters = 0.0;
        var weekWorkoutCount = 0;
        var weekCalories = 0.0;

        for (final doc in sessions) {
          final data = doc.data();
          final startedAt = DateTime.tryParse(
            data['startedAt'] as String? ?? '',
          );
          if (startedAt == null || startedAt.isBefore(weekStart)) {
            continue;
          }
          weekWorkoutCount += 1;
          weekDistanceMeters +=
              (data['distanceMeters'] as num?)?.toDouble() ?? 0;
          weekCalories += (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
          children: [
            Text(
              'Welcome, $displayName',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Your weekly momentum at a glance.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ProgressMetricCard(
                    label: 'Distance',
                    value:
                        '${(weekDistanceMeters / 1000).toStringAsFixed(2)} km',
                    icon: Icons.route,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProgressMetricCard(
                    label: 'Workouts',
                    value: '$weekWorkoutCount',
                    icon: Icons.fitness_center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProgressMetricCard(
              label: 'Calories',
              value: '${weekCalories.toStringAsFixed(0)} kcal',
              icon: Icons.local_fire_department,
              fullWidth: true,
            ),
            const SizedBox(height: 18),
            Text(
              'Recent Sessions',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (sessions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No workouts yet.'),
                ),
              )
            else
              ...sessions.take(5).map((doc) {
                final data = doc.data();
                final startedAt = DateTime.tryParse(
                  data['startedAt'] as String? ?? '',
                );
                final endedAt = DateTime.tryParse(
                  data['endedAt'] as String? ?? '',
                );
                final distanceMeters =
                    (data['distanceMeters'] as num?)?.toDouble() ?? 0;
                final calories =
                    (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
                final elevation =
                    (data['elevationGainMeters'] as num?)?.toDouble() ?? 0;
                final durationSeconds = (startedAt != null && endedAt != null)
                    ? endedAt.difference(startedAt).inSeconds
                    : 0;
                final pace = durationSeconds > 0 && distanceMeters > 0
                    ? (durationSeconds / 60) / (distanceMeters / 1000)
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _kBrandOrange.withValues(alpha: 0.15),
                        foregroundColor: _kBrandOrange,
                        child: const Icon(Icons.directions_run),
                      ),
                      title: Text(
                        '${(distanceMeters / 1000).toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${_formatSessionDuration(startedAt, endedAt)} · ${pace > 0 ? '${pace.toStringAsFixed(2)} min/km' : '-- min/km'} · ${calories.toStringAsFixed(0)} kcal · +${elevation.toStringAsFixed(0)} m',
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.displayName,
    required this.onLogout,
  });

  final String displayName;
  final Future<void> Function() onLogout;

  Future<void> _openHistory(BuildContext context) async {
    if (Firebase.apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firebase is not ready yet.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutHistoryPage(
          firestore: FirebaseFirestore.instance,
          onShareMessage: (message) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
        ),
      ),
    );
  }

  Future<void> _openAccountSecurity(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No signed-in user found.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AccountSecurityPage(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Unknown';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      children: [
        Text(
          'Profile',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _kBrandOrange,
                  foregroundColor: Colors.white,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'R',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(email),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Account Security'),
                subtitle: const Text('Change email or password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openAccountSecurity(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Workout History'),
                subtitle: const Text('Browse past runs and export GPX'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openHistory(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                subtitle: const Text('Sign out of the app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressMetricCard extends StatelessWidget {
  const _ProgressMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kBrandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _kBrandOrange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatSessionDuration(DateTime? startedAt, DateTime? endedAt) {
  if (startedAt == null || endedAt == null) {
    return '--:--:--';
  }
  final elapsed = endedAt.difference(startedAt);
  final h = elapsed.inHours;
  final m = elapsed.inMinutes.remainder(60);
  final s = elapsed.inSeconds.remainder(60);
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isSubmitting = false;
  bool _isCreateAccount = false;
  bool _hidePassword = true;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final displayName = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorText = 'Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorText = 'Password must be at least 6 characters.');
      return;
    }
    if (_isCreateAccount && displayName.isEmpty) {
      setState(() => _errorText = 'Please enter a display name.');
      return;
    }
    if (_isCreateAccount && password != _confirmPasswordController.text) {
      setState(() => _errorText = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      if (_isCreateAccount) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final createdUser = credential.user;
        if (createdUser != null) {
          await createdUser.updateDisplayName(displayName);
          await createdUser.sendEmailVerification();
          await createdUser.reload();
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _errorText = _humanizeAuthError(error));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = 'Authentication failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email for reset.')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_humanizeAuthError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF181818), Color(0xFF222222), Color(0xFF2C2C2C)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
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
                          color: _kBrandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'FAKESTRAVA',
                          style: TextStyle(
                            color: _kBrandOrange,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _isCreateAccount ? 'Create Account' : 'Welcome Back',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isCreateAccount
                            ? 'Sign up with email and password.'
                            : 'Sign in with Firebase Authentication.',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 18),
                      if (_isCreateAccount)
                        TextField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                      if (_isCreateAccount) const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _hidePassword,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() => _hidePassword = !_hidePassword);
                            },
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                      if (_isCreateAccount) const SizedBox(height: 12),
                      if (_isCreateAccount)
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _hidePassword,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_person_outlined),
                          ),
                        ),
                      if (_errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _errorText!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _isCreateAccount
                                    ? Icons.person_add_alt_1
                                    : Icons.login,
                              ),
                        label: Text(
                          _isSubmitting
                              ? (_isCreateAccount
                                    ? 'Creating account...'
                                    : 'Signing in...')
                              : (_isCreateAccount ? 'Create Account' : 'Login'),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: _kBrandOrange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _isCreateAccount = !_isCreateAccount;
                                      _errorText = null;
                                    });
                                  },
                            child: Text(
                              _isCreateAccount
                                  ? 'Already have an account? Sign in'
                                  : 'Create new account',
                            ),
                          ),
                          const Spacer(),
                          if (!_isCreateAccount)
                            TextButton(
                              onPressed: _isSubmitting ? null : _resetPassword,
                              child: const Text('Forgot password?'),
                            ),
                        ],
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
      ).showSnackBar(SnackBar(content: Text(_humanizeAuthError(error))));
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
      backgroundColor: _kSurface,
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
                          color: _kBrandOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'ACTION REQUIRED',
                          style: TextStyle(
                            color: _kBrandOrange,
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

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key, required this.user});

  final User user;

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _currentPasswordForEmailController =
      TextEditingController();
  final TextEditingController _currentPasswordForPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmNewPasswordController =
      TextEditingController();

  bool _updatingEmail = false;
  bool _updatingPassword = false;

  @override
  void initState() {
    super.initState();
    _newEmailController.text = widget.user.email ?? '';
  }

  @override
  void dispose() {
    _newEmailController.dispose();
    _currentPasswordForEmailController.dispose();
    _currentPasswordForPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  Future<void> _reauthenticate({required String currentPassword}) async {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw StateError('Signed-in account does not have an email address.');
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
  }

  Future<void> _changeEmail() async {
    final newEmail = _newEmailController.text.trim();
    final currentPassword = _currentPasswordForEmailController.text;

    if (newEmail.isEmpty || !newEmail.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid new email.')),
      );
      return;
    }
    if (currentPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your current password to change email.'),
        ),
      );
      return;
    }

    setState(() => _updatingEmail = true);
    try {
      await _reauthenticate(currentPassword: currentPassword);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('User session expired. Sign in again.');
      }
      await user.verifyBeforeUpdateEmail(newEmail);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verification sent to $newEmail. Open that inbox and confirm to finalize email change.',
          ),
        ),
      );
      _currentPasswordForEmailController.clear();
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_humanizeAuthError(error))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _updatingEmail = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final currentPassword = _currentPasswordForPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmNewPassword = _confirmNewPasswordController.text;

    if (currentPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your current password to change password.'),
        ),
      );
      return;
    }
    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 6 characters.'),
        ),
      );
      return;
    }
    if (newPassword != confirmNewPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password confirmation does not match.'),
        ),
      );
      return;
    }

    setState(() => _updatingPassword = true);
    try {
      await _reauthenticate(currentPassword: currentPassword);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('User session expired. Sign in again.');
      }
      await user.updatePassword(newPassword);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      _currentPasswordForPasswordController.clear();
      _newPasswordController.clear();
      _confirmNewPasswordController.clear();
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_humanizeAuthError(error))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _updatingPassword = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Unknown';
    return Scaffold(
      appBar: AppBar(title: const Text('Account Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Email',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text('Current email: $email'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'New email',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _currentPasswordForEmailController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _updatingEmail ? null : _changeEmail,
                    icon: _updatingEmail
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.email_outlined),
                    label: Text(
                      _updatingEmail
                          ? 'Updating email...'
                          : 'Send email change verification',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _currentPasswordForPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      prefixIcon: Icon(Icons.lock_reset),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      prefixIcon: Icon(Icons.lock_open_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmNewPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _updatingPassword ? null : _changePassword,
                    icon: _updatingPassword
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.password_outlined),
                    label: Text(
                      _updatingPassword
                          ? 'Updating password...'
                          : 'Update password',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrackingHomePage extends StatefulWidget {
  const TrackingHomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<TrackingHomePage> createState() => _TrackingHomePageState();
}

class _TrackingHomePageState extends State<TrackingHomePage> {
  static const LatLng _defaultCenter = LatLng(3.1390, 101.6869);
  final TrackingBackgroundService _service = TrackingBackgroundService();
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
  final List<LatLng> _routePoints = <LatLng>[];
  StreamSubscription<TrackingSnapshot>? _snapshotSubscription;
  StreamSubscription<Position>? _foregroundPositionSubscription;
  Timer? _voiceTimer;

  bool _isTracking = false;
  bool _isAutoPaused = false;
  bool _isStarting = false;
  bool _isStopping = false;
  bool _voicePaceEnabled = true;
  bool _hasLiveLocationFix = false;
  bool _hasCenteredOnLiveLocation = false;
  bool _followUserLocation = true;
  String? _locationStatus;
  double _distanceKm = 0;
  double _elevationGainMeters = 0;
  double _caloriesKcal = 0;
  int _points = 0;
  DateTime? _startedAt;
  String? _activeRouteSessionId;
  LatLng? _currentPosition;
  LatLng _mapCenter = _defaultCenter;
  double _mapZoom = 15.5;

  @override
  void initState() {
    super.initState();
    _hydrateState();
    _startForegroundPointerStream();
    _setupVoicePace();
    _snapshotSubscription = _service.updates.listen((
      TrackingSnapshot snapshot,
    ) {
      if (!mounted) {
        return;
      }
      final wasTracking = _isTracking;
      setState(() {
        if (snapshot.sessionId != null &&
            snapshot.sessionId != _activeRouteSessionId &&
            snapshot.isTracking) {
          _activeRouteSessionId = snapshot.sessionId;
          _routePoints.clear();
        }
        _isTracking = snapshot.isTracking;
        _isAutoPaused = snapshot.isAutoPaused;
        _distanceKm = snapshot.distanceMeters / 1000;
        _elevationGainMeters = snapshot.elevationGainMeters;
        _caloriesKcal = snapshot.caloriesKcal;
        _points = snapshot.points;
        _startedAt = snapshot.startedAt;
        if (snapshot.isTracking) {
          _capturePoint(snapshot);
        } else if (!_hasLiveLocationFix) {
          _currentPosition = null;
          _mapCenter = _defaultCenter;
          _routePoints.clear();
        }
      });
      if (!wasTracking && _isTracking) {
        _startVoiceAnnouncements();
      } else if (wasTracking && !_isTracking) {
        _stopVoiceAnnouncements();
      }
    });
  }

  @override
  void dispose() {
    _snapshotSubscription?.cancel();
    _foregroundPositionSubscription?.cancel();
    _stopVoiceAnnouncements();
    _tts.stop();
    super.dispose();
  }

  Future<void> _setupVoicePace() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42);
  }

  void _startVoiceAnnouncements() {
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _announcePace();
    });
  }

  void _stopVoiceAnnouncements() {
    _voiceTimer?.cancel();
    _voiceTimer = null;
  }

  Future<void> _announcePace() async {
    if (!_voicePaceEnabled ||
        !_isTracking ||
        _isAutoPaused ||
        _distanceKm <= 0) {
      return;
    }
    final pace = _paceMinPerKm();
    if (pace <= 0) {
      return;
    }
    final wholeMinutes = pace.floor();
    final seconds = ((pace - wholeMinutes) * 60).round();
    await _tts.speak(
      'Current pace $wholeMinutes minutes ${seconds.clamp(0, 59)} seconds per kilometer',
    );
  }

  Future<void> _hydrateState() async {
    final snapshot = await _service.restoreLatestSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _isTracking = snapshot.isTracking;
      _isAutoPaused = snapshot.isAutoPaused;
      _distanceKm = snapshot.distanceMeters / 1000;
      _elevationGainMeters = snapshot.elevationGainMeters;
      _caloriesKcal = snapshot.caloriesKcal;
      _points = snapshot.points;
      _startedAt = snapshot.startedAt;
      _activeRouteSessionId = snapshot.sessionId;
      if (snapshot.isTracking) {
        _capturePoint(snapshot);
      } else {
        _currentPosition = null;
        _mapCenter = _defaultCenter;
        _routePoints.clear();
      }
    });
    if (_isTracking) {
      _startVoiceAnnouncements();
    }
  }

  void _capturePoint(TrackingSnapshot snapshot) {
    final latitude = snapshot.latitude;
    final longitude = snapshot.longitude;
    if (latitude == null || longitude == null) {
      return;
    }
    final point = LatLng(latitude, longitude);
    if (!_hasLiveLocationFix) {
      _currentPosition = point;
    }
    if (_routePoints.length <= 1) {
      _mapCenter = point;
    }
    if (_routePoints.isEmpty ||
        _routePoints.last.latitude != point.latitude ||
        _routePoints.last.longitude != point.longitude) {
      _routePoints.add(point);
    }
  }

  Future<void> _startForegroundPointerStream() async {
    if (kIsWeb) {
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() => _locationStatus = 'Turn on location services');
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _locationStatus = 'Location permission required');
      }
      return;
    }

    await _foregroundPositionSubscription?.cancel();
    try {
      final initial = await Geolocator.getCurrentPosition(
        locationSettings: _buildLocationSettings(),
      );
      _applyLivePosition(initial);
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _applyLivePosition(lastKnown);
        }
      } catch (_) {}
    }

    _foregroundPositionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _buildLocationSettings(),
        ).listen(
          (Position position) => _applyLivePosition(position),
          onError: (_) {
            if (mounted) {
              setState(() => _locationStatus = 'Waiting for GPS signal...');
            }
          },
        );
  }

  void _applyLivePosition(Position position) {
    if (!mounted) {
      return;
    }
    final point = LatLng(position.latitude, position.longitude);
    final shouldCenterNow = !_hasCenteredOnLiveLocation;
    setState(() {
      _hasLiveLocationFix = true;
      _currentPosition = point;
      _locationStatus = position.isMocked
          ? 'Mock location detected on device'
          : null;
      if (shouldCenterNow) {
        _hasCenteredOnLiveLocation = true;
        _mapCenter = point;
      }
    });
    if (_followUserLocation || shouldCenterNow) {
      _mapCenter = point;
      _mapController.move(_mapCenter, _mapZoom);
    }
  }

  LocationSettings _buildLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );
  }

  void _zoomMap(double delta) {
    final nextZoom = (_mapZoom + delta).clamp(3.0, 18.0).toDouble();
    _mapController.move(_mapCenter, nextZoom);
  }

  void _recenterToUser() {
    final point = _currentPosition;
    if (point == null) {
      return;
    }
    setState(() {
      _followUserLocation = true;
      _mapCenter = point;
    });
    _mapController.move(_mapCenter, _mapZoom);
  }

  double _paceMinPerKm() {
    if (_startedAt == null || _distanceKm <= 0) {
      return 0;
    }
    final elapsedMinutes =
        DateTime.now().difference(_startedAt!).inSeconds / 60;
    return elapsedMinutes / _distanceKm;
  }

  String _elapsedLabel() {
    if (_startedAt == null) {
      return '--:--:--';
    }
    final Duration elapsed = DateTime.now().difference(_startedAt!);
    final int h = elapsed.inHours;
    final int m = elapsed.inMinutes.remainder(60);
    final int s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onTap,
    required BorderRadius borderRadius,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kBrandOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pace = _paceMinPerKm();
    final zoomControlsTop = MediaQuery.paddingOf(context).top + 104;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _mapZoom,
                onPositionChanged: (position, hasGesture) {
                  final center = position.center;
                  final zoom = position.zoom;
                  if (center != null) {
                    _mapCenter = center;
                  }
                  if (zoom != null) {
                    _mapZoom = zoom;
                  }
                  if (hasGesture) {
                    _followUserLocation = false;
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.company.fakestrava',
                ),
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: Colors.deepOrange,
                      ),
                    ],
                  ),
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition!,
                        width: 34,
                        height: 34,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _kBrandOrange,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              child: Container(
                height: 160,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            top: zoomControlsTop,
            child: Column(
              children: [
                _buildZoomButton(
                  icon: Icons.my_location,
                  onTap: _recenterToUser,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(height: 8),
                _buildZoomButton(
                  icon: Icons.add,
                  onTap: () => _zoomMap(1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                const SizedBox(height: 2),
                _buildZoomButton(
                  icon: Icons.remove,
                  onTap: () => _zoomMap(-1),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isTracking
                                  ? Icons.directions_run
                                  : Icons.pause_circle,
                              size: 18,
                              color: _isTracking
                                  ? _kBrandOrange
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isTracking
                                  ? (_isAutoPaused
                                        ? 'Auto-paused'
                                        : 'Tracking Active')
                                  : 'Ready to Start',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _buildTopActionButton(
                        icon: _voicePaceEnabled
                            ? Icons.volume_up
                            : Icons.volume_off,
                        onTap: () {
                          setState(
                            () => _voicePaceEnabled = !_voicePaceEnabled,
                          );
                        },
                        tooltip: _voicePaceEnabled
                            ? 'Disable voice pace'
                            : 'Enable voice pace',
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kBrandBlack.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 20,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                label: 'Distance',
                                value: '${_distanceKm.toStringAsFixed(3)} km',
                                icon: Icons.route,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildStatTile(
                                label: 'Pace',
                                value: pace == 0
                                    ? '-- min/km'
                                    : '${pace.toStringAsFixed(2)} min/km',
                                icon: Icons.speed,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                label: 'Calories',
                                value:
                                    '${_caloriesKcal.toStringAsFixed(0)} kcal',
                                icon: Icons.local_fire_department,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildStatTile(
                                label: 'Elevation',
                                value:
                                    '${_elevationGainMeters.toStringAsFixed(0)} m',
                                icon: Icons.terrain,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatTile(
                                label: 'Elapsed',
                                value: _elapsedLabel(),
                                icon: Icons.timer_outlined,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildStatTile(
                                label: 'Points',
                                value: '$_points',
                                icon: Icons.location_on_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: kIsWeb || _isTracking || _isStarting
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        setState(() {
                                          _isStarting = true;
                                          _followUserLocation = true;
                                        });
                                        try {
                                          await _service.startTracking();
                                          await _startForegroundPointerStream();
                                        } catch (error) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isStarting = false);
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(
                                  _isStarting ? 'Starting...' : 'Start',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kBrandOrange,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    !kIsWeb && _isTracking && !_isStopping
                                    ? () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        setState(() => _isStopping = true);
                                        try {
                                          await _service.stopTracking();
                                        } catch (error) {
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isStopping = false);
                                          }
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.stop_rounded),
                                label: Text(
                                  _isStopping ? 'Stopping...' : 'Stop',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                  minimumSize: const Size.fromHeight(46),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Tracking is disabled on web. Use Android/iOS for live GPS.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ] else if (_locationStatus != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _locationStatus!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({
    super.key,
    required this.firestore,
    required this.onShareMessage,
  });

  final FirebaseFirestore firestore;
  final ValueChanged<String> onShareMessage;

  Future<void> _exportSessionGpx(String sessionId) async {
    final pointSnapshots = await firestore
        .collection('tracking_sessions')
        .doc(sessionId)
        .collection('points')
        .orderBy('timestamp')
        .get();
    if (pointSnapshots.docs.isEmpty) {
      onShareMessage('No points found for this workout.');
      return;
    }
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<gpx version="1.1" creator="Fake Strava">')
      ..writeln('  <trk>')
      ..writeln('    <name>Fake Strava Workout</name>')
      ..writeln('    <trkseg>');
    for (final doc in pointSnapshots.docs) {
      final data = doc.data();
      final lat = (data['latitude'] as num?)?.toDouble();
      final lon = (data['longitude'] as num?)?.toDouble();
      final time = data['timestamp'] as String?;
      if (lat == null || lon == null) {
        continue;
      }
      buffer.writeln('      <trkpt lat="$lat" lon="$lon">');
      if (time != null) {
        buffer.writeln('        <time>$time</time>');
      }
      buffer.writeln('      </trkpt>');
    }
    buffer
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    await Clipboard.setData(ClipboardData(text: utf8.decode(bytes)));
    onShareMessage('GPX copied to clipboard. Paste it into a .gpx file.');
  }

  String _formatDuration(DateTime? startedAt, DateTime? endedAt) {
    if (startedAt == null || endedAt == null) {
      return '--:--:--';
    }
    final elapsed = endedAt.difference(startedAt);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout History'),
        backgroundColor: _kBrandBlack,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: firestore
            .collection('tracking_sessions')
            .orderBy('startedAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final errorText = snapshot.error.toString().toLowerCase();
            final missingDefaultDatabase = errorText.contains(
              'database (default) does not exist',
            );
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  missingDefaultDatabase
                      ? 'Cloud history is unavailable because Firestore is not set up for this project yet.\n\nOpen Firebase Console -> Firestore Database and create the default database.'
                      : 'Unable to load workout history.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sessions = snapshot.data!.docs;
          if (sessions.isEmpty) {
            return const Center(child: Text('No workouts yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sessions.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = sessions[index].data();
              final sessionId = sessions[index].id;
              final startedAt = DateTime.tryParse(
                data['startedAt'] as String? ?? '',
              );
              final endedAt = DateTime.tryParse(
                data['endedAt'] as String? ?? '',
              );
              final distanceMeters =
                  (data['distanceMeters'] as num?)?.toDouble() ?? 0;
              final calories = (data['caloriesKcal'] as num?)?.toDouble() ?? 0;
              final elevation =
                  (data['elevationGainMeters'] as num?)?.toDouble() ?? 0;
              final distanceKm = distanceMeters / 1000;
              final durationSeconds = (startedAt != null && endedAt != null)
                  ? endedAt.difference(startedAt).inSeconds
                  : 0;
              final pace = durationSeconds > 0 && distanceKm > 0
                  ? (durationSeconds / 60) / distanceKm
                  : 0.0;
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  title: Text(
                    '${distanceKm.toStringAsFixed(2)} km',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_formatDuration(startedAt, endedAt)}  |  ${pace > 0 ? '${pace.toStringAsFixed(2)} min/km' : '-- min/km'}  |  ${calories.toStringAsFixed(0)} kcal  |  +${elevation.toStringAsFixed(0)} m',
                    ),
                  ),
                  trailing: IconButton.filledTonal(
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: () => _exportSessionGpx(sessionId),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
