import 'package:flutter/material.dart';

const Color kBrandOrange = Color(0xFFFC4C02);
const Color kBrandBlack = Color(0xFF121212);
const Color kSurface = Color(0xFFF4F5F7);
const Color kSurfaceCard = Color(0xFFFFFFFF);

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
