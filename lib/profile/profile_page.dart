import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/core/ui_components.dart';
import 'package:fake_strava/auth/pages/account_security_page.dart';
import 'package:fake_strava/tracking/pages/workout_history_page.dart';
import 'user_metrics.dart';
import 'user_metrics_form_dialog.dart';
import 'user_metrics_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.displayName,
    required this.onLogout,
  });

  final String displayName;
  final Future<void> Function() onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late UserMetricsRepository _metricsRepository;
  UserMetrics? _userMetrics;
  bool _ghostMode = false;

  String _metricsErrorMessage(Object error, {required bool isSave}) {
    if (error is FirebaseException) {
      final message = error.message?.toLowerCase() ?? '';
      final missingDatabase =
          error.code == 'not-found' &&
          (message.contains('database (default) does not exist') ||
              message.contains('database fakestrava does not exist'));
      if (missingDatabase) {
        return 'Cloud database is not provisioned yet. Open Firebase Console and create Firestore database "fakestrava".';
      }
    }

    final action = isSave ? 'saving' : 'loading';
    return 'Error $action metrics: $error';
  }

  @override
  void initState() {
    super.initState();
    _metricsRepository = UserMetricsRepository();
    _loadUserMetrics();
    _loadGhostMode();
  }

  Future<void> _loadGhostMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ghostMode = prefs.getBool('ghost_mode') ?? false;
    });
  }

  Future<void> _setGhostMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ghost_mode', value);
    setState(() {
      _ghostMode = value;
    });
  }

  Future<void> _loadUserMetrics() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final metrics = await _metricsRepository.getUserMetrics(user.uid);
      setState(() {
        _userMetrics = metrics;
      });
    } catch (e) {
      if (mounted) {
        AppNotification.show(
          context: context,
          message: _metricsErrorMessage(e, isSave: false),
          type: NotificationType.error,
        );
      }
    }
  }

  Future<void> _showMetricsDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => UserMetricsFormDialog(
        initialMetrics: _userMetrics,
        onSave: (metrics) async {
          try {
            await _metricsRepository.saveUserMetrics(user.uid, metrics);
            setState(() {
              _userMetrics = metrics;
            });
            if (mounted) {
              AppNotification.show(
                context: context,
                message: 'Metrics saved successfully',
                type: NotificationType.success,
              );
            }
          } catch (e) {
            if (mounted) {
              AppNotification.show(
                context: context,
                message: _metricsErrorMessage(e, isSave: true),
                type: NotificationType.error,
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    if (Firebase.apps.isEmpty) {
      AppNotification.show(
        context: context,
        message: 'Firebase is not ready yet.',
        type: NotificationType.error,
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
            AppNotification.show(
              context: context,
              message: message,
              type: NotificationType.info,
            );
          },
        ),
      ),
    );
  }

  Future<void> _openAccountSecurity(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppNotification.show(
        context: context,
        message: 'No signed-in user found.',
        type: NotificationType.error,
      );
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
                  backgroundColor: kBrandOrange,
                  foregroundColor: Colors.white,
                  child: Text(
                    widget.displayName.isNotEmpty
                        ? widget.displayName[0].toUpperCase()
                        : 'R',
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
                        widget.displayName,
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.monitor_weight_outlined),
                    const SizedBox(width: 12),
                    const Text(
                      'Your Metrics',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showMetricsDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
                if (_userMetrics != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Height',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '${_userMetrics!.heightCm.toStringAsFixed(1)} cm',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Weight',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '${_userMetrics!.weightKg.toStringAsFixed(1)} kg',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Age',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '${_userMetrics!.age} years',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Gender',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            _userMetrics!.gender == 'M' ? 'Male' : 'Female',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No metrics set. Add your metrics for accurate calorie tracking.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Ghost Mode'),
                subtitle: const Text('Hide your location from other runners'),
                trailing: Switch(value: _ghostMode, onChanged: _setGhostMode),
                onTap: () => _setGhostMode(!_ghostMode),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                subtitle: const Text('Sign out of the app'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onLogout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
