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
    return Container(
      color: kSurface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
          children: [
            const _ProfilePageHeader(),
            const SizedBox(height: 20),
            _ProfileHeroCard(
              displayName: widget.displayName,
              email: email,
            ),
            const SizedBox(height: 24),
            const _ProfileSectionHeader(
              title: 'Your metrics',
              subtitle: 'Used for calorie estimates and personalization',
            ),
            const SizedBox(height: 14),
            _ProfileMetricsGlowCard(
              userMetrics: _userMetrics,
              onEdit: _showMetricsDialog,
            ),
            const SizedBox(height: 24),
            const _ProfileSectionHeader(
              title: 'Account & preferences',
              subtitle: 'Security, history, and visibility',
            ),
            const SizedBox(height: 14),
            _ProfileActionsGlowCard(
              ghostMode: _ghostMode,
              onGhostModeChanged: _setGhostMode,
              onAccountSecurity: () => _openAccountSecurity(context),
              onHistory: () => _openHistory(context),
              onLogout: widget.onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Shared visual language with Progress page --------------------------------

BoxDecoration _profileGlowCardDecoration({Color accent = kBrandOrange}) {
  return BoxDecoration(
    color: kSurfaceCard,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: accent.withValues(alpha: 0.12),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: accent.withValues(alpha: 0.06),
        blurRadius: 14,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

class _ProfilePageHeader extends StatelessWidget {
  const _ProfilePageHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kBrandOrange.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Profile',
              style: AppTypography.displaySmall.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const Icon(
            Icons.person,
            color: kBrandOrange,
            size: 32,
          ),
        ],
      ),
    );
  }
}

class _ProfileHeroCard extends StatefulWidget {
  const _ProfileHeroCard({
    required this.displayName,
    required this.email,
  });

  final String displayName;
  final String email;

  @override
  State<_ProfileHeroCard> createState() => _ProfileHeroCardState();
}

class _ProfileHeroCardState extends State<_ProfileHeroCard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'fakestrava',
  );

  Widget _buildFollowerStatChip({
    required int count,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFF97316)),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final initial = widget.displayName.isNotEmpty
        ? widget.displayName[0].toUpperCase()
        : 'R';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() ?? const <String, dynamic>{};
        final username = userData['username'] as String? ?? user.uid.substring(0, 6);
        final followingIds = ((userData['followingIds'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);
        final followingCount = followingIds.length;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('users')
              .where('followingIds', arrayContains: user.uid)
              .snapshots(),
          builder: (context, followersSnapshot) {
            final followerCount = followersSnapshot.data?.docs.length ?? 0;

            return Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF97316).withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: AppTypography.displaySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                            Text(
                              widget.displayName,
                              style: AppTypography.headingLarge.copyWith(
                                color: const Color(0xFF1E293B),
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.email,
                              style: AppTypography.bodySmall.copyWith(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@$username',
                              style: AppTypography.bodySmall.copyWith(
                                color: const Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildFollowerStatChip(
                                  count: followerCount,
                                  label: 'followers',
                                  icon: Icons.people_outline_rounded,
                                ),
                                _buildFollowerStatChip(
                                  count: followingCount,
                                  label: 'following',
                                  icon: Icons.person_add_alt_1_outlined,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            );
          },
        );
      },
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.headingLarge.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: AppTypography.bodySmall.copyWith(
              color: Colors.black.withValues(alpha: 0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfileMetricsGlowCard extends StatelessWidget {
  const _ProfileMetricsGlowCard({
    required this.userMetrics,
    required this.onEdit,
  });

  final UserMetrics? userMetrics;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    const accent = kInfo;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _profileGlowCardDecoration(accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProfileAccentIconBadge(
                icon: Icons.monitor_weight_outlined,
                accent: accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Body stats',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: kBrandOrange,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (userMetrics != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: 'Height',
                  value: '${userMetrics!.heightCm.toStringAsFixed(1)} cm',
                ),
                _MetricChip(
                  label: 'Weight',
                  value: '${userMetrics!.weightKg.toStringAsFixed(1)} kg',
                ),
                _MetricChip(
                  label: 'Age',
                  value: '${userMetrics!.age} years',
                ),
                _MetricChip(
                  label: 'Gender',
                  value: userMetrics!.gender == 'M' ? 'Male' : 'Female',
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'No metrics set. Add your metrics for accurate calorie tracking.',
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: Colors.black.withValues(alpha: 0.5),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.black.withValues(alpha: 0.88),
          ),
        ),
      ],
    );
  }
}

class _ProfileAccentIconBadge extends StatelessWidget {
  const _ProfileAccentIconBadge({
    required this.icon,
    required this.accent,
  });

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.2),
            accent.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: accent, size: 24),
    );
  }
}

class _ProfileActionsGlowCard extends StatelessWidget {
  const _ProfileActionsGlowCard({
    required this.ghostMode,
    required this.onGhostModeChanged,
    required this.onAccountSecurity,
    required this.onHistory,
    required this.onLogout,
  });

  final bool ghostMode;
  final ValueChanged<bool> onGhostModeChanged;
  final VoidCallback onAccountSecurity;
  final VoidCallback onHistory;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _profileGlowCardDecoration(),
      child: Column(
        children: [
          _ProfileActionRow(
            icon: Icons.manage_accounts_outlined,
            accent: kBrandOrange,
            title: 'Account Security',
            subtitle: 'Change email or password',
            trailing: const Icon(Icons.chevron_right, color: kTextTertiary),
            onTap: onAccountSecurity,
          ),
          Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
          _ProfileActionRow(
            icon: Icons.history_rounded,
            accent: kSuccess,
            title: 'Workout History',
            subtitle: 'Browse past runs and export GPX',
            trailing: const Icon(Icons.chevron_right, color: kTextTertiary),
            onTap: onHistory,
          ),
          Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const _ProfileAccentIconBadge(
                  icon: Icons.visibility_off_outlined,
                  accent: kWarning,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ghost Mode',
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hide your location from other runners',
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.black.withValues(alpha: 0.52),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: ghostMode,
                  onChanged: onGhostModeChanged,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
          _ProfileActionRow(
            icon: Icons.logout_rounded,
            accent: kError,
            title: 'Logout',
            subtitle: 'Sign out of the app',
            trailing: const Icon(Icons.chevron_right, color: kTextTertiary),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text(
                    'Are you sure you want to sign out of the app?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kError,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(true),
                      child: const Text('Log Out'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              await onLogout();
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileActionRow extends StatelessWidget {
  const _ProfileActionRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _ProfileAccentIconBadge(icon: icon, accent: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.black.withValues(alpha: 0.52),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
