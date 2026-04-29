import 'package:flutter/material.dart';

// ============================================================================
// COLOR PALETTE
// ============================================================================

const Color kBrandOrange = Color(0xFFFC4C02);
const Color kBrandOrangeLight = Color(0xFFFFEADD);
const Color kBrandOrangeMedium = Color(0xFFFF8A52);
const Color kBrandBlack = Color(0xFF121212);
const Color kSurface = Color(0xFFF4F5F7);
const Color kSurfaceCard = Color(0xFFFFFFFF);

// Semantic colors for accessibility
const Color kSuccess = Color(0xFF2E7D32);
const Color kSuccessLight = Color(0xFFE8F5E9);
const Color kWarning = Color(0xFFFFA726);
const Color kWarningLight = Color(0xFFFFF3E0);
const Color kError = Color(0xFFD32F2F);
const Color kErrorLight = Color(0xFFFFEBEE);
const Color kInfo = Color(0xFF1976D2);
const Color kInfoLight = Color(0xFFE3F2FD);

// Neutral grays for minimalist design
const Color kTextPrimary = Color(0xFF1F2937);
const Color kTextSecondary = Color(0xFF6B7280);
const Color kTextTertiary = Color(0xFF9CA3AF);
const Color kDisabled = Color(0xFFE5E7EB);
const Color kDivider = Color(0xFFF3F4F6);

// ============================================================================
// SPACING & SIZING
// ============================================================================

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppBorderRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

class AppShadow {
  static const BoxShadow xs = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 2,
    offset: Offset(0, 1),
  );

  static const BoxShadow sm = BoxShadow(
    color: Color(0x0F000000),
    blurRadius: 3,
    offset: Offset(0, 1),
  );

  static const BoxShadow md = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static const BoxShadow lg = BoxShadow(
    color: Color(0x1F000000),
    blurRadius: 16,
    offset: Offset(0, 4),
  );

  static const BoxShadow xl = BoxShadow(
    color: Color(0x28000000),
    blurRadius: 24,
    offset: Offset(0, 8),
  );

  static const BoxShadow elevated = BoxShadow(
    color: Color(0x33000000),
    blurRadius: 32,
    offset: Offset(0, 12),
  );
}

// ============================================================================
// TYPOGRAPHY
// ============================================================================

class AppTypography {
  // Display styles (large headings)
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: kTextPrimary,
    height: 1.1,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: kTextPrimary,
    height: 1.15,
    letterSpacing: -0.3,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: kTextPrimary,
    height: 1.2,
  );

  // Heading styles
  static const TextStyle headingLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: kTextPrimary,
    height: 1.25,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: kTextPrimary,
    height: 1.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: kTextPrimary,
    height: 1.35,
  );

  // Body styles
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: kTextPrimary,
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: kTextPrimary,
    height: 1.42,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: kTextSecondary,
    height: 1.43,
  );

  // Label styles
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: kTextPrimary,
    height: 1.43,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: kTextPrimary,
    height: 1.43,
    letterSpacing: 0.1,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: kTextSecondary,
    height: 1.45,
    letterSpacing: 0.15,
  );

  // Caption & helper text
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: kTextSecondary,
    height: 1.43,
  );

  static const TextStyle captionSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: kTextTertiary,
    height: 1.45,
  );
}

// ============================================================================
// ANIMATION CURVES & DURATIONS
// ============================================================================

class AppAnimation {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration verySlow = Duration(milliseconds: 800);

  static const Curve easeInOut = Curves.easeInOut;
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeIn = Curves.easeIn;
  static const Curve bouncy = Curves.elasticOut;
}

class MapThemeOption {
  const MapThemeOption({
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

const List<MapThemeOption> kMapThemeOptions = <MapThemeOption>[
  MapThemeOption(
    label: 'OSM Standard',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors',
  ),
  MapThemeOption(
    label: 'OSM Humanitarian',
    urlTemplate: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
    attribution: 'OpenStreetMap contributors, HOT',
    subdomains: <String>['a', 'b', 'c'],
  ),
  MapThemeOption(
    label: 'OSM Light',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: 'OpenStreetMap contributors, CARTO',
    subdomains: <String>['a', 'b', 'c', 'd'],
  ),
  MapThemeOption(
    label: 'OSM Dark',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: 'OpenStreetMap contributors, CARTO',
    subdomains: <String>['a', 'b', 'c', 'd'],
  ),
];
