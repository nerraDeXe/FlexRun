import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'tracking/models/tracking_snapshot.dart';
import 'tracking/services/tracking_background_service.dart';
import 'tracking/services/bluetooth_hr_service.dart';

const Color _kBrandOrange = Color(0xFFFC4C02);
const Color _kBrandBlack = Color(0xFF121212);
const Color _kSurface = Color(0xFFF4F5F7);
const Color _kSurfaceCard = Color(0xFFFFFFFF);

class _MapThemeOption {
  const _MapThemeOption({
    required this.label,
    required this.urlTemplate,
    required this.attribution,
    this.subdomains = const <String>[],
  });

  final String label;
  final String urlTemplate;
  final String attribution;
  final List<String> subdomains;
}

const List<_MapThemeOption> _kMapThemeOptions = <_MapThemeOption>[
  _MapThemeOption(
    label: 'OSM Standard',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors',
  ),
  _MapThemeOption(
    label: 'OSM Humanitarian',
    urlTemplate: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors, HOT',
    subdomains: <String>['a', 'b', 'c'],
  ),
  _MapThemeOption(
    label: 'OSM Light',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: 'OpenStreetMap contributors, CARTO',
    subdomains: <String>['a', 'b', 'c', 'd'],
  ),
  _MapThemeOption(
    label: 'OSM Dark',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: 'OpenStreetMap contributors, CARTO',
    subdomains: <String>['a', 'b', 'c', 'd'],
  ),
];

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

    final userId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instanceFor(
                app: Firebase.app(),
                databaseId: 'fakestrava',
              )
              .collection('tracking_sessions')
              .where('userId', isEqualTo: userId)
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
                final durationSeconds =
                    (data['activeDurationSeconds'] as num?)?.toInt() ??
                    ((startedAt != null && endedAt != null)
                        ? endedAt.difference(startedAt).inSeconds
                        : 0);
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
                        '${_formatSessionDuration(startedAt, endedAt, durationSeconds: durationSeconds)} · ${pace > 0 ? '${pace.toStringAsFixed(2)} min/km' : '-- min/km'} · ${calories.toStringAsFixed(0)} kcal · +${elevation.toStringAsFixed(0)} m',
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
          firestore: FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'fakestrava',
          ),
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

String _formatSessionDuration(
  DateTime? startedAt,
  DateTime? endedAt, {
  int? durationSeconds,
}) {
  Duration? elapsed;
  if (durationSeconds != null && durationSeconds > 0) {
    elapsed = Duration(seconds: durationSeconds);
  } else if (startedAt != null && endedAt != null) {
    elapsed = endedAt.difference(startedAt);
  }
  if (elapsed == null) {
    return '--:--:--';
  }
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
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

class _TrackingHomePageState extends State<TrackingHomePage>
    with SingleTickerProviderStateMixin {
  static const LatLng _defaultCenter = LatLng(3.1390, 101.6869);
  final TrackingBackgroundService _service = TrackingBackgroundService();
  final BluetoothHRService _hrService = BluetoothHRService();
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
  final List<LatLng> _routePoints = <LatLng>[];
  StreamSubscription<TrackingSnapshot>? _snapshotSubscription;
  StreamSubscription<Position>? _foregroundPositionSubscription;
  StreamSubscription<int>? _hrSubscription;
  Timer? _voiceTimer;
  Timer? _liveMetricsTimer;
  Timer? _finishHoldTimer;

  bool _isTracking = false;
  bool _isAutoPaused = false;
  bool _isManuallyPaused = false;
  bool _isStarting = false;
  bool _isPausing = false;
  bool _isResuming = false;
  bool _isFinishing = false;
  late final AnimationController _panelController;
  bool _isMapFullscreen = false;
  double _finishHoldProgress = 0;
  double _panelDragAccumulator = 0;
  double _statsScale = 1.0;
  bool _voicePaceEnabled = true;
  bool _hasLiveLocationFix = false;
  bool _hasCenteredOnLiveLocation = false;
  bool _followUserLocation = true;
  String? _locationStatus;
  double _distanceKm = 0;
  double _previewDistanceKm = 0;
  double _elevationGainMeters = 0;
  double _caloriesKcal = 0;
  int _points = 0;
  int _elapsedSeconds = 0;
  DateTime? _elapsedSnapshotCapturedAt;
  DateTime? _startedAt;
  String? _activeRouteSessionId;
  LatLng? _currentPosition;
  LatLng? _lastTrackedPoint;
  LatLng _mapCenter = _defaultCenter;
  double _mapZoom = 15.5;
  int _mapThemeIndex = 0;
  int _currentHeartRate = 0;
  final List<int> _heartRateReadings = <int>[];

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _panelController.addListener(() => setState(() {}));
    _hydrateState();
    _startForegroundPointerStream();
    _setupVoicePace();
    _setupHRMonitoring();
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
        _isManuallyPaused = snapshot.isManuallyPaused;
        _distanceKm = snapshot.distanceMeters / 1000;
        _previewDistanceKm = _distanceKm;
        _elevationGainMeters = snapshot.elevationGainMeters;
        _caloriesKcal = snapshot.caloriesKcal;
        _points = snapshot.points;
        _elapsedSeconds = snapshot.elapsedSeconds;
        _elapsedSnapshotCapturedAt = DateTime.now();
        _startedAt = snapshot.startedAt;
        if (snapshot.isTracking) {
          _capturePoint(snapshot);
        } else {
          _activeRouteSessionId = null;
          _lastTrackedPoint = null;
          _routePoints.clear();
          _currentHeartRate = 0;
          _heartRateReadings.clear();
          if (!_hasLiveLocationFix) {
            _currentPosition = null;
            _mapCenter = _defaultCenter;
          }
        }
      });
      if (!wasTracking && _isTracking) {
        _startVoiceAnnouncements();
      } else if (wasTracking && !_isTracking) {
        _cancelFinishHold();
        _stopVoiceAnnouncements();
      }
      _syncLiveMetricsTimer();
    });
  }

  @override
  void dispose() {
    _snapshotSubscription?.cancel();
    _foregroundPositionSubscription?.cancel();
    _hrSubscription?.cancel();
    _finishHoldTimer?.cancel();
    _stopVoiceAnnouncements();
    _stopLiveMetricsTimer();
    _tts.stop();
    _hrService.dispose();
    _panelController.dispose();
    super.dispose();
  }

  Future<void> _setupVoicePace() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42);
  }

  void _setupHRMonitoring() {
    _hrSubscription?.cancel();
    _hrSubscription = _hrService.hrValueStream.listen((heartRate) {
      if (mounted && _isTracking) {
        setState(() {
          _currentHeartRate = heartRate;
          _heartRateReadings.add(heartRate);
        });
      }
    });
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
    final distanceKm = _displayDistanceKm();
    if (!_voicePaceEnabled || !_isTracking || _isPaused || distanceKm <= 0) {
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
      _isManuallyPaused = snapshot.isManuallyPaused;
      _distanceKm = snapshot.distanceMeters / 1000;
      _previewDistanceKm = _distanceKm;
      _elevationGainMeters = snapshot.elevationGainMeters;
      _caloriesKcal = snapshot.caloriesKcal;
      _points = snapshot.points;
      _elapsedSeconds = snapshot.elapsedSeconds;
      _elapsedSnapshotCapturedAt = DateTime.now();
      _startedAt = snapshot.startedAt;
      _activeRouteSessionId = snapshot.sessionId;
      if (snapshot.isTracking) {
        _capturePoint(snapshot);
      } else {
        _activeRouteSessionId = null;
        _lastTrackedPoint = null;
        _currentPosition = null;
        _mapCenter = _defaultCenter;
        _routePoints.clear();
      }
    });
    if (_isTracking) {
      _startVoiceAnnouncements();
    }
    _syncLiveMetricsTimer();
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
    _lastTrackedPoint = point;
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
    _updatePreviewDistance(point, position.accuracy);
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

  void _updatePreviewDistance(LatLng current, double accuracyMeters) {
    if (!_isTracking || _isPaused || accuracyMeters > 30) {
      return;
    }
    final anchor = _lastTrackedPoint;
    if (anchor == null) {
      return;
    }
    final previewMeters = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      current.latitude,
      current.longitude,
    );
    if (previewMeters < 0.5 || previewMeters > 150) {
      return;
    }
    final nextDistanceKm = _distanceKm + (previewMeters / 1000);
    if (nextDistanceKm <= _previewDistanceKm + 0.0001) {
      return;
    }
    setState(() {
      _previewDistanceKm = nextDistanceKm;
    });
  }

  void _syncLiveMetricsTimer() {
    _stopLiveMetricsTimer();
    if (!_isTracking) {
      return;
    }
    _liveMetricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _stopLiveMetricsTimer() {
    _liveMetricsTimer?.cancel();
    _liveMetricsTimer = null;
  }

  double _displayDistanceKm() => math.max(_distanceKm, _previewDistanceKm);

  bool get _isPaused => _isAutoPaused || _isManuallyPaused;

  int _activeElapsedSeconds() {
    if (!_isTracking || _isPaused) {
      return _elapsedSeconds;
    }
    final capturedAt = _elapsedSnapshotCapturedAt;
    if (capturedAt == null) {
      return _elapsedSeconds;
    }
    final extra = DateTime.now().difference(capturedAt).inSeconds;
    return _elapsedSeconds + (extra > 0 ? extra : 0);
  }

  double _paceMinPerKm() {
    final distanceKm = _displayDistanceKm();
    if (distanceKm <= 0) {
      return 0;
    }
    final elapsedMinutes = _activeElapsedSeconds() / 60;
    if (elapsedMinutes <= 0) {
      return 0;
    }
    return elapsedMinutes / distanceKm;
  }

  void _cycleMapTheme() {
    setState(() {
      _mapThemeIndex = (_mapThemeIndex + 1) % _kMapThemeOptions.length;
    });
  }

  bool get _canHoldToFinish =>
      !kIsWeb && _isTracking && !_isStarting && !_isPausing && !_isResuming;

  void _startFinishHold() {
    if (!_canHoldToFinish || _isFinishing) {
      return;
    }
    HapticFeedback.mediumImpact();
    _finishHoldTimer?.cancel();
    final startedAt = DateTime.now();
    setState(() {
      _finishHoldProgress = 0;
    });
    _finishHoldTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final nextProgress = (elapsedMs / 3000).clamp(0.0, 1.0);
      if (nextProgress >= 1.0) {
        timer.cancel();
        _finishHoldTimer = null;
        HapticFeedback.heavyImpact();
        _finishWorkout();
        return;
      }
      setState(() {
        _finishHoldProgress = nextProgress;
      });
    });
  }

  void _cancelFinishHold() {
    if (_isFinishing) {
      return;
    }
    _finishHoldTimer?.cancel();
    _finishHoldTimer = null;
    if (_finishHoldProgress > 0) {
      setState(() {
        _finishHoldProgress = 0;
      });
    }
  }

  void _resetTrackingPanelState() {
    _finishHoldTimer?.cancel();
    _finishHoldTimer = null;
    _stopVoiceAnnouncements();
    _stopLiveMetricsTimer();
    _isTracking = false;
    _isAutoPaused = false;
    _isManuallyPaused = false;
    _distanceKm = 0;
    _previewDistanceKm = 0;
    _elevationGainMeters = 0;
    _caloriesKcal = 0;
    _points = 0;
    _elapsedSeconds = 0;
    _elapsedSnapshotCapturedAt = null;
    _startedAt = null;
    _activeRouteSessionId = null;
    _lastTrackedPoint = null;
    _routePoints.clear();
    _finishHoldProgress = 0;
  }

  Future<void> _finishWorkout() async {
    if (_isFinishing) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isFinishing = true;
      _finishHoldProgress = 1;
    });
    try {
      await _service.stopTracking();
      if (!mounted) {
        return;
      }
      setState(() {
        _resetTrackingPanelState();
        _isFinishing = false;
        _finishHoldProgress = 0;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Workout saved. Great effort!')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isFinishing = false;
        _finishHoldProgress = 0;
      });
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _elapsedLabel() {
    if (_startedAt == null && _elapsedSeconds == 0) {
      return '--:--:--';
    }
    final elapsed = Duration(seconds: _activeElapsedSeconds());
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _trackingStatusLabel {
    if (!_isTracking) {
      return 'Ready';
    }
    if (_isManuallyPaused) {
      return 'Paused';
    }
    if (_isAutoPaused) {
      return 'Auto-paused';
    }
    return 'Recording';
  }

  Color get _trackingStatusColor {
    if (!_isTracking) {
      return const Color(0xFF607D8B);
    }
    if (_isPaused) {
      return const Color(0xFFFFA726);
    }
    return const Color(0xFF2E7D32);
  }

  Widget _buildIconGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool active = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: active
            ? _kBrandOrange.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white, size: 20),
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }

  Widget _buildPrimaryMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final scale = _statsScale;
    return Container(
      padding: EdgeInsets.all(14 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 34 * scale,
            height: 34 * scale,
            decoration: BoxDecoration(
              color: _kBrandOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _kBrandOrange, size: 18 * scale),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    value,
                    key: ValueKey<String>('primary_${label}_$value'),
                    style: TextStyle(
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w800,
                      color: _kBrandBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryMetric({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final scale = _statsScale;
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16 * scale, color: _kBrandOrange),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    value,
                    key: ValueKey<String>('secondary_${label}_$value'),
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w700,
                      color: _kBrandBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStart() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isStarting = true;
      _followUserLocation = true;
    });
    try {
      HapticFeedback.lightImpact();
      await _service.startTracking();
      await _startForegroundPointerStream();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _handlePauseResume() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      if (_isManuallyPaused) {
        _isResuming = true;
      } else {
        _isPausing = true;
      }
    });
    try {
      HapticFeedback.lightImpact();
      if (_isManuallyPaused) {
        await _service.resumeTracking();
      } else {
        await _service.pauseTracking();
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isPausing = false;
          _isResuming = false;
        });
      }
    }
  }

  bool get _isPanelCollapsed => _panelController.value < 0.5;

  void _togglePanelCollapse() {
    if (_isMapFullscreen) return;
    if (_panelController.value > 0.5) {
      _panelController.reverse();
    } else {
      _panelController.forward();
    }
  }

  void _onPanelDragStart(DragStartDetails details) {
    if (_isMapFullscreen) return;
    _panelController.stop();
  }

  void _onPanelDragUpdate(DragUpdateDetails details) {
    if (_isMapFullscreen) return;
    final delta = details.primaryDelta;
    if (delta == null) return;
    // Delta > 0 means dragging down (shrinking)
    _panelController.value -= delta / 180.0;
  }

  void _onPanelDragEnd(DragEndDetails details) {
    if (_isMapFullscreen) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300) {
      _panelController.reverse(); // Fling down
    } else if (velocity < -300) {
      _panelController.forward(); // Fling up
    } else if (_panelController.value > 0.5) {
      _panelController.forward();
    } else {
      _panelController.reverse();
    }
  }

  void _toggleMapFullscreen() {
    setState(() {
      _isMapFullscreen = !_isMapFullscreen;
    });
  }

  void _cycleStatsScale() {
    setState(() {
      if (_statsScale < 1.0) {
        _statsScale = 1.0;
      } else if (_statsScale < 1.1) {
        _statsScale = 1.2;
      } else {
        _statsScale = 0.9;
      }
    });
  }

  Future<void> _showHRDeviceSelector() async {
    final permitted = await _hrService.requestPermissions();
    if (!permitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth permissions required')),
        );
      }
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildHRDevicePicker(),
    );
  }

  Widget _buildHRDevicePicker() {
    return StatefulBuilder(
      builder: (context, setState) {
        return StreamBuilder<List<ScanResult>>(
          stream: _hrService.scanForDevices().asBroadcastStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final devices = snapshot.data ?? [];
            if (devices.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No Bluetooth devices found',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_hrService.isConnected)
                      ElevatedButton(
                        onPressed: () async {
                          await _hrService.disconnect();
                          if (mounted) {
                            setState(() {});
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Disconnect'),
                      ),
                  ],
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                final isConnected =
                    _hrService.connectedDevice?.remoteId ==
                    device.device.remoteId;

                return ListTile(
                  title: Text(
                    device.device.platformName.isEmpty
                        ? 'Unknown Device'
                        : device.device.platformName,
                  ),
                  subtitle: Text(device.device.remoteId.str),
                  trailing: isConnected
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: isConnected
                      ? null
                      : () async {
                          final success = await _hrService.connectToDevice(
                            device.device,
                          );
                          if (mounted) {
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Connected to HR monitor'),
                                ),
                              );
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to connect to device'),
                                ),
                              );
                            }
                          }
                        },
                );
              },
            );
          },
        );
      },
    );
  }

  String get _statsScaleLabel {
    if (_statsScale < 1.0) {
      return 'S';
    }
    if (_statsScale > 1.1) {
      return 'L';
    }
    return 'M';
  }

  @override
  Widget build(BuildContext context) {
    final pace = _paceMinPerKm();
    final displayedDistanceKm = _displayDistanceKm();
    final activeMapTheme = _kMapThemeOptions[_mapThemeIndex];
    final avgSpeedKmh = pace > 0 ? 60 / pace : 0.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final mapControlsBottom = _isMapFullscreen
        ? 20.0 + bottomInset
        : (340.0 + (30.0 * _panelController.value)) + bottomInset;
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
                  _mapCenter = position.center;
                  _mapZoom = position.zoom;
                  if (hasGesture) {
                    _followUserLocation = false;
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: activeMapTheme.urlTemplate,
                  subdomains: activeMapTheme.subdomains,
                  userAgentPackageName: 'com.company.fakestrava',
                ),
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 6,
                        color: _kBrandOrange,
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
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(activeMapTheme.attribution),
                  ],
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.28),
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.36),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _trackingStatusColor,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _trackingStatusLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildIconGlassButton(
                            icon: _voicePaceEnabled
                                ? Icons.volume_up
                                : Icons.volume_off,
                            onTap: () {
                              setState(() => _voicePaceEnabled = !_voicePaceEnabled);
                            },
                            active: _voicePaceEnabled,
                            tooltip: _voicePaceEnabled
                                ? 'Disable voice pace'
                                : 'Enable voice pace',
                          ),
                          const SizedBox(width: 4),
                          _buildIconGlassButton(
                            icon: Icons.layers_outlined,
                            onTap: _cycleMapTheme,
                            tooltip: 'Map style: ${activeMapTheme.label}',
                          ),
                          const SizedBox(width: 4),
                          _buildIconGlassButton(
                            icon: Icons.text_fields_rounded,
                            onTap: _cycleStatsScale,
                            tooltip: 'Stats size: $_statsScaleLabel',
                            active: _statsScale > 1.0,
                          ),
                          const SizedBox(width: 4),
                          _buildIconGlassButton(
                            icon: Icons.favorite,
                            onTap: _showHRDeviceSelector,
                            tooltip: _hrService.isConnected
                                ? 'HR Monitor Connected'
                                : 'Connect HR Monitor',
                            active: _hrService.isConnected,
                          ),
                          const SizedBox(width: 4),
                          _buildIconGlassButton(
                            icon: _isMapFullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            onTap: _toggleMapFullscreen,
                            tooltip: _isMapFullscreen
                                ? 'Exit full screen map'
                                : 'Full screen map',
                            active: _isMapFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: mapControlsBottom,
            child: IgnorePointer(
              ignoring: _panelController.value > 0.5,
              child: FadeTransition(
                opacity: ReverseAnimation(_panelController),
                child: Column(
              children: [
                _buildIconGlassButton(
                  icon: Icons.my_location,
                  onTap: _recenterToUser,
                  active: _followUserLocation,
                  tooltip: 'Center on location',
                ),
                const SizedBox(height: 8),
                _buildIconGlassButton(
                  icon: Icons.add,
                  onTap: () => _zoomMap(1),
                  tooltip: 'Zoom in',
                ),
                const SizedBox(height: 8),
                _buildIconGlassButton(
                  icon: Icons.remove,
                  onTap: () => _zoomMap(-1),
                  tooltip: 'Zoom out',
                ),
              ],
            ),
              ),
            ),
          ),
          if (!_isMapFullscreen)
            Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onPanelDragStart,
                onVerticalDragUpdate: _onPanelDragUpdate,
                onVerticalDragEnd: _onPanelDragEnd,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + bottomInset),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2F000000),
                        blurRadius: 24,
                        offset: Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      GestureDetector(
                        onTap: _togglePanelCollapse,
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                width: 42,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Icon(
                                _isPanelCollapsed
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: Colors.black45,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _elapsedLabel(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: _kBrandBlack,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _trackingStatusColor.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _trackingStatusLabel,
                              style: TextStyle(
                                color: _trackingStatusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildPrimaryMetric(
                              label: 'Distance',
                              value:
                                  '${displayedDistanceKm.toStringAsFixed(3)} km',
                              icon: Icons.route,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildPrimaryMetric(
                              label: 'Pace',
                              value: pace > 0
                                  ? '${pace.toStringAsFixed(2)} min/km'
                                  : '-- min/km',
                              icon: Icons.speed,
                            ),
                          ),
                        ],
                      ),
                      SizeTransition(
                        sizeFactor: ReverseAnimation(_panelController),
                        axisAlignment: -1.0,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Summary mode. Swipe up for full details.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizeTransition(
                        sizeFactor: _panelController,
                        axisAlignment: -1.0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Calories',
                                value:
                                    '${_caloriesKcal.toStringAsFixed(0)} kcal',
                                icon: Icons.local_fire_department,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Elevation',
                                value:
                                    '${_elevationGainMeters.toStringAsFixed(0)} m',
                                icon: Icons.terrain,
                              ),
                            ),
                        ],
                      ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Points',
                                value: '$_points',
                                icon: Icons.location_on_outlined,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Avg Speed',
                                value: avgSpeedKmh > 0
                                    ? '${avgSpeedKmh.toStringAsFixed(2)} km/h'
                                    : '-- km/h',
                                icon: Icons.flash_on,
                              ),
                            ),
                        ],
                      ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Current HR',
                                value: _currentHeartRate > 0
                                    ? '$_currentHeartRate bpm'
                                    : '-- bpm',
                                icon: Icons.favorite,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildSecondaryMetric(
                                label: 'Avg HR',
                                value: _heartRateReadings.isNotEmpty
                                    ? '${((_heartRateReadings.fold<int>(0, (a, b) => a + b) / _heartRateReadings.length)).round()} bpm'
                                    : '-- bpm',
                                icon: Icons.favorite_outline,
                              ),
                            ),
                        ],
                      ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Chip(
                              avatar: Icon(
                                _hasLiveLocationFix
                                    ? Icons.gps_fixed
                                    : Icons.gps_not_fixed,
                                color: _hasLiveLocationFix
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFE65100),
                                size: 16,
                              ),
                              label: Text(
                                _hasLiveLocationFix
                                    ? 'GPS locked'
                                    : 'Searching GPS',
                              ),
                            ),
                            Chip(
                              avatar: const Icon(Icons.map_outlined, size: 16),
                              label: Text(activeMapTheme.label),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _canHoldToFinish
                              ? 'Press and hold Finish for 3 seconds to save workout'
                              : 'Start a workout to enable pause and finish',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: kIsWeb || _isTracking || _isStarting
                                  ? null
                                  : _handleStart,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                _isStarting ? 'Starting...' : 'Start',
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  !kIsWeb &&
                                      _isTracking &&
                                      !_isPausing &&
                                      !_isResuming
                                  ? _handlePauseResume
                                  : null,
                              icon: Icon(
                                _isManuallyPaused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              label: Text(
                                _isManuallyPaused
                                    ? (_isResuming ? 'Resuming...' : 'Resume')
                                    : (_isPausing ? 'Pausing...' : 'Pause'),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: _kBrandBlack,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: _canHoldToFinish
                                  ? (_) => _startFinishHold()
                                  : null,
                              onTapUp: (_) => _cancelFinishHold(),
                              onTapCancel: _cancelFinishHold,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF20242E),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: _finishHoldProgress,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: _kBrandOrange.withValues(
                                              alpha: 0.9,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isFinishing
                                            ? Icons.check_circle
                                            : Icons.stop_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _isFinishing
                                            ? 'Saving...'
                                            : _finishHoldProgress > 0
                                            ? 'Hold ${(3 - (_finishHoldProgress * 3)).ceil().clamp(1, 3)}s'
                                            : 'Finish',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (kIsWeb) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Tracking is disabled on web. Use Android/iOS for live GPS.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ] else if (_locationStatus != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _locationStatus!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
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

  String _formatDuration(
    DateTime? startedAt,
    DateTime? endedAt, {
    int? durationSeconds,
  }) {
    Duration? elapsed;
    if (durationSeconds != null && durationSeconds > 0) {
      elapsed = Duration(seconds: durationSeconds);
    } else if (startedAt != null && endedAt != null) {
      elapsed = endedAt.difference(startedAt);
    }
    if (elapsed == null) {
      return '--:--:--';
    }
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final s = elapsed.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatWorkoutDate(DateTime? startedAt) {
    if (startedAt == null) {
      return 'Unknown date';
    }
    final local = startedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final workoutDay = DateTime(local.year, local.month, local.day);
    final dayDiff = today.difference(workoutDay).inDays;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (dayDiff == 0) {
      return 'Today, $hh:$mm';
    }
    if (dayDiff == 1) {
      return 'Yesterday, $hh:$mm';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  Widget _metricPill({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _kBrandOrange),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _summaryMetricBox({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
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
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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
          var totalDistanceKm = 0.0;
          var totalDurationSeconds = 0;
          var longestDistanceKm = 0.0;
          for (final session in sessions) {
            final data = session.data();
            final distanceMeters =
                (data['distanceMeters'] as num?)?.toDouble() ?? 0;
            final distanceKm = distanceMeters / 1000;
            final startedAt = DateTime.tryParse(
              data['startedAt'] as String? ?? '',
            );
            final endedAt = DateTime.tryParse(data['endedAt'] as String? ?? '');
            final durationSeconds =
                (data['activeDurationSeconds'] as num?)?.toInt() ??
                ((startedAt != null && endedAt != null)
                    ? endedAt.difference(startedAt).inSeconds
                    : 0);
            totalDistanceKm += distanceKm;
            totalDurationSeconds += durationSeconds > 0 ? durationSeconds : 0;
            if (distanceKm > longestDistanceKm) {
              longestDistanceKm = distanceKm;
            }
          }
          final averagePace = totalDistanceKm > 0
              ? (totalDurationSeconds / 60) / totalDistanceKm
              : 0.0;
          return RefreshIndicator(
            onRefresh: () async =>
                Future<void>.delayed(const Duration(milliseconds: 300)),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: sessions.length + 1,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Training Snapshot',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Total Distance',
                                  value:
                                      '${totalDistanceKm.toStringAsFixed(2)} km',
                                  icon: Icons.route,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Total Time',
                                  value: _formatDuration(
                                    null,
                                    null,
                                    durationSeconds: totalDurationSeconds,
                                  ),
                                  icon: Icons.timer_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Avg Pace',
                                  value: averagePace > 0
                                      ? '${averagePace.toStringAsFixed(2)} min/km'
                                      : '-- min/km',
                                  icon: Icons.speed,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _summaryMetricBox(
                                  label: 'Longest Run',
                                  value:
                                      '${longestDistanceKm.toStringAsFixed(2)} km',
                                  icon: Icons.flag_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final sessionIndex = index - 1;
                final data = sessions[sessionIndex].data();
                final sessionId = sessions[sessionIndex].id;
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
                final distanceKm = distanceMeters / 1000;
                final points = (data['points'] as num?)?.toInt() ?? 0;
                final status = (data['status'] as String?) ?? 'stopped';
                final durationSeconds =
                    (data['activeDurationSeconds'] as num?)?.toInt() ??
                    ((startedAt != null && endedAt != null)
                        ? endedAt.difference(startedAt).inSeconds
                        : 0);
                final pace = durationSeconds > 0 && distanceKm > 0
                    ? (durationSeconds / 60) / distanceKm
                    : 0.0;
                final avgSpeedKmh = durationSeconds > 0 && distanceKm > 0
                    ? distanceKm / (durationSeconds / 3600)
                    : 0.0;
                final isFinished = status == 'stopped';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${distanceKm.toStringAsFixed(2)} km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatWorkoutDate(startedAt),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isFinished
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isFinished ? 'Finished' : status.toUpperCase(),
                                style: TextStyle(
                                  color: isFinished
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE65100),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              tooltip: 'Export GPX',
                              icon: const Icon(Icons.file_download_outlined),
                              onPressed: () => _exportSessionGpx(sessionId),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _metricPill(
                              icon: Icons.timer_outlined,
                              label: 'Time',
                              value: _formatDuration(
                                startedAt,
                                endedAt,
                                durationSeconds: durationSeconds,
                              ),
                            ),
                            _metricPill(
                              icon: Icons.speed,
                              label: 'Pace',
                              value: pace > 0
                                  ? '${pace.toStringAsFixed(2)} min/km'
                                  : '-- min/km',
                            ),
                            _metricPill(
                              icon: Icons.flash_on,
                              label: 'Speed',
                              value: avgSpeedKmh > 0
                                  ? '${avgSpeedKmh.toStringAsFixed(2)} km/h'
                                  : '-- km/h',
                            ),
                            _metricPill(
                              icon: Icons.local_fire_department,
                              label: 'Calories',
                              value: '${calories.toStringAsFixed(0)} kcal',
                            ),
                            _metricPill(
                              icon: Icons.terrain,
                              label: 'Elev',
                              value: '+${elevation.toStringAsFixed(0)} m',
                            ),
                            _metricPill(
                              icon: Icons.location_on_outlined,
                              label: 'Points',
                              value: '$points',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
