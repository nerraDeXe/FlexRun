import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fake_strava/core/theme.dart';
import 'package:fake_strava/progress/progress_page.dart';
import 'package:fake_strava/profile/profile_page.dart';
import 'package:fake_strava/tracking/pages/tracking_home_page.dart';

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
          indicatorColor: kBrandOrange.withValues(alpha: 0.20),
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
              selectedIcon: Icon(Icons.directions_run, color: kBrandOrange),
              label: 'Track',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.insights, color: kBrandOrange),
              label: 'Progress',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: Colors.white70),
              selectedIcon: Icon(Icons.person, color: kBrandOrange),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

