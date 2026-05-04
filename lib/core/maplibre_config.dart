const String kMapTilerKey = String.fromEnvironment('MAPTILER_KEY');
const String kMapStyleUrl = String.fromEnvironment('MAP_STYLE_URL');
const String kMapTerrainUrl = String.fromEnvironment('MAP_TERRAIN_URL');
const String kMapTerrainEncoding =
    String.fromEnvironment('MAP_TERRAIN_ENCODING', defaultValue: 'mapbox');

String get kResolvedMapStyleUrl {
  if (kMapStyleUrl.isNotEmpty) {
    return kMapStyleUrl;
  }
  if (kMapTilerKey.isNotEmpty) {
    return 'https://api.maptiler.com/maps/streets-v2/style.json?key=$kMapTilerKey';
  }
  return '';
}

String get kResolvedMapTerrainUrl {
  if (kMapTerrainUrl.isNotEmpty) {
    return kMapTerrainUrl;
  }
  if (kMapTilerKey.isNotEmpty) {
    return 'https://api.maptiler.com/tiles/terrain-rgb/tiles.json?key=$kMapTilerKey';
  }
  return '';
}
