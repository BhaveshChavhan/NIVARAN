import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import '../models/safety_models.dart';
import 'offline_tile_provider.dart';

/// Service managing on-device map tile caching and safety zone persistence.
/// When the user is in network range, the map and safety zones are cached locally.
/// When offline or in low-network areas, the cached tiles and zones are rendered seamlessly.
class OfflineMapService extends ChangeNotifier {
  Directory? _tilesDir;
  File? _zonesFile;

  bool _isInitialized = false;
  bool _isOffline = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  int _cachedTilesCount = 0;
  double _cachedSizeMb = 0.0;
  String _cachedAreaName = 'Default Safety Zones';
  DateTime? _lastCachedAt;

  List<CrimeHotspot> _cachedHotspots = [];
  List<SafePlace> _cachedSafePlaces = [];

  Timer? _connectivityTimer;
  Timer? _debounceStatsTimer;

  bool get isInitialized => _isInitialized;
  bool get isOffline => _isOffline;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String get downloadStatus => _downloadStatus;

  int get cachedTilesCount => _cachedTilesCount;
  double get cachedSizeMb => _cachedSizeMb;
  String get cachedAreaName => _cachedAreaName;
  DateTime? get lastCachedAt => _lastCachedAt;

  List<CrimeHotspot> get cachedHotspots => _cachedHotspots;
  List<SafePlace> get cachedSafePlaces => _cachedSafePlaces;

  TileProvider get tileProvider => OfflineTileProvider(offlineMapService: this);

  OfflineMapService() {
    init();
  }

  /// Initialize local directories, load cached safety zones, and start connectivity monitoring
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _tilesDir = Directory('${appDocDir.path}/offline_maps/tiles');
      if (!await _tilesDir!.exists()) {
        await _tilesDir!.create(recursive: true);
      }

      _zonesFile = File('${appDocDir.path}/offline_maps/cached_zones.json');
      await _loadOrInitializeZones();
      await _calculateStorageStats();

      // Check initial connectivity
      await checkConnectivity();

      // Periodic connectivity check (every 12 seconds)
      _connectivityTimer?.cancel();
      _connectivityTimer = Timer.periodic(const Duration(seconds: 12), (_) {
        checkConnectivity();
      });

      _isInitialized = true;
      notifyListeners();
      debugPrint('[OfflineMapService] Initialized with $_cachedTilesCount cached tiles (${_cachedSizeMb.toStringAsFixed(2)} MB)');
    } catch (e) {
      debugPrint('[OfflineMapService] Initialization error: $e');
    }
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _debounceStatsTimer?.cancel();
    super.dispose();
  }

  // ─── Network Status Monitoring ─────────────────────────────────────────────

  Future<void> checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('tile.openstreetmap.org')
          .timeout(const Duration(seconds: 3));
      final connected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (_isOffline == connected) {
        _isOffline = !connected;
        notifyListeners();
        debugPrint('[OfflineMapService] Network status changed: isOffline=$_isOffline');
      }
    } catch (_) {
      if (!_isOffline) {
        _isOffline = true;
        notifyListeners();
        debugPrint('[OfflineMapService] Network status changed: isOffline=true (offline)');
      }
    }
  }

  // ─── Zone Persistence (Crime Hotspots & Safe Places) ────────────────────────

  Future<void> _loadOrInitializeZones() async {
    if (_zonesFile != null && await _zonesFile!.exists()) {
      try {
        final content = await _zonesFile!.readAsString();
        if (content.isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          final bundle = OfflineZoneBundle.fromJson(data);
          _cachedHotspots = bundle.hotspots;
          _cachedSafePlaces = bundle.safePlaces;
          _cachedAreaName = bundle.areaName;
          _lastCachedAt = bundle.cachedAt;
          debugPrint('[OfflineMapService] Loaded ${_cachedHotspots.length} hotspots & ${_cachedSafePlaces.length} safe places from local disk');
          return;
        }
      } catch (e) {
        debugPrint('[OfflineMapService] Error reading cached zones, falling back to defaults: $e');
      }
    }

    // Default static bootstrap
    _cachedHotspots = SafetyModels.getCrimeHotspots();
    _cachedSafePlaces = SafetyModels.getSafePlaces();
    _lastCachedAt = DateTime.now();
    await saveZonesLocally(
      hotspots: _cachedHotspots,
      safePlaces: _cachedSafePlaces,
      areaName: 'Default Maharashtra Zones (Nashik & Nagpur)',
    );
  }

  /// Persists the latest safety zones to local storage so they are always available offline
  Future<void> saveZonesLocally({
    List<CrimeHotspot>? hotspots,
    List<SafePlace>? safePlaces,
    String? areaName,
    double? centerLat,
    double? centerLng,
    double? radiusKm,
  }) async {
    if (hotspots != null) _cachedHotspots = List.from(hotspots);
    if (safePlaces != null) _cachedSafePlaces = List.from(safePlaces);
    if (areaName != null) _cachedAreaName = areaName;
    _lastCachedAt = DateTime.now();

    try {
      if (_zonesFile != null) {
        if (!await _zonesFile!.parent.exists()) {
          await _zonesFile!.parent.create(recursive: true);
        }

        final bundle = OfflineZoneBundle(
          areaName: _cachedAreaName,
          centerLat: centerLat ?? 19.9975,
          centerLng: centerLng ?? 73.7898,
          radiusKm: radiusKm ?? 5.0,
          cachedAt: _lastCachedAt!,
          hotspots: _cachedHotspots,
          safePlaces: _cachedSafePlaces,
        );

        await _zonesFile!.writeAsString(jsonEncode(bundle.toJson()), flush: true);
        notifyListeners();
        debugPrint('[OfflineMapService] Saved ${_cachedHotspots.length} hotspots and ${_cachedSafePlaces.length} safe places for offline use');
      }
    } catch (e) {
      debugPrint('[OfflineMapService] Error saving zones locally: $e');
    }
  }

  // ─── Tile File Access ───────────────────────────────────────────────────────

  File getTileFile(int z, int x, int y) {
    return File('${_tilesDir?.path ?? ""}/$z/$x/$y.png');
  }

  bool hasTile(int z, int x, int y) {
    final file = getTileFile(z, x, y);
    return file.existsSync() && file.lengthSync() > 0;
  }

  void onTileAdded() {
    _debounceStatsTimer?.cancel();
    _debounceStatsTimer = Timer(const Duration(seconds: 2), () {
      _calculateStorageStats();
    });
  }

  Future<void> _calculateStorageStats() async {
    if (_tilesDir == null || !await _tilesDir!.exists()) {
      _cachedTilesCount = 0;
      _cachedSizeMb = 0.0;
      notifyListeners();
      return;
    }

    try {
      int count = 0;
      int totalBytes = 0;

      final entities = _tilesDir!.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.png')) {
          count++;
          totalBytes += entity.lengthSync();
        }
      }

      _cachedTilesCount = count;
      _cachedSizeMb = totalBytes / (1024 * 1024);
      notifyListeners();
    } catch (e) {
      debugPrint('[OfflineMapService] Error calculating storage stats: $e');
    }
  }

  // ─── Proactive Area & Zone Pre-caching ──────────────────────────────────────

  /// Download and store map tiles for a specified geographic radius and zoom range.
  /// Also stores all current safety hotspots and safe places for that zone.
  Future<void> downloadZoneMap({
    required double centerLat,
    required double centerLng,
    double radiusKm = 5.0,
    String areaName = 'Local Zone',
    int minZoom = 12,
    int maxZoom = 15,
    List<CrimeHotspot>? hotspots,
    List<SafePlace>? safePlaces,
  }) async {
    if (_isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _downloadStatus = 'Calculating zone tiles for $areaName...';
    notifyListeners();

    // 1. Save safety zones locally first
    await saveZonesLocally(
      hotspots: hotspots ?? _cachedHotspots,
      safePlaces: safePlaces ?? _cachedSafePlaces,
      areaName: areaName,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radiusKm,
    );

    try {
      // 2. Compute bounding box coordinates
      // Approx 111.32 km per degree latitude
      final deltaLat = radiusKm / 111.32;
      final deltaLng = radiusKm / (111.32 * math.cos(centerLat * math.pi / 180.0));

      final minLat = centerLat - deltaLat;
      final maxLat = centerLat + deltaLat;
      final minLng = centerLng - deltaLng;
      final maxLng = centerLng + deltaLng;

      // 3. Collect list of tiles to download across zoom levels
      final List<Map<String, int>> tilesToFetch = [];

      for (int z = minZoom; z <= maxZoom; z++) {
        final minX = _lon2tileX(minLng, z).clamp(0, (1 << z) - 1);
        final maxX = _lon2tileX(maxLng, z).clamp(0, (1 << z) - 1);
        // In Web Mercator, latitude decreases as Y increases
        final minY = _lat2tileY(maxLat, z).clamp(0, (1 << z) - 1);
        final maxY = _lat2tileY(minLat, z).clamp(0, (1 << z) - 1);

        for (int x = minX; x <= maxX; x++) {
          for (int y = minY; y <= maxY; y++) {
            if (!hasTile(z, x, y)) {
              tilesToFetch.add({'z': z, 'x': x, 'y': y});
            }
          }
        }
      }

      final totalTiles = tilesToFetch.length;
      debugPrint('[OfflineMapService] Downloading $totalTiles missing tiles for $areaName');

      if (totalTiles == 0) {
        _downloadProgress = 1.0;
        _downloadStatus = 'Map for $areaName is already 100% cached offline!';
        _isDownloading = false;
        await _calculateStorageStats();
        notifyListeners();
        return;
      }

      int completed = 0;
      final dio = Dio();

      // Download in parallel with pool of 4 concurrent workers
      const poolSize = 4;
      int nextIdx = 0;

      Future<void> worker() async {
        while (nextIdx < totalTiles) {
          final idx = nextIdx++;
          final tile = tilesToFetch[idx];
          final z = tile['z']!;
          final x = tile['x']!;
          final y = tile['y']!;

          final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
          final targetFile = getTileFile(z, x, y);

          try {
            final response = await dio.get<List<int>>(
              url,
              options: Options(
                responseType: ResponseType.bytes,
                headers: {
                  'User-Agent': 'NivaranSafetyApp/1.0 (Offline Map Caching)',
                },
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

            if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
              if (!await targetFile.parent.exists()) {
                await targetFile.parent.create(recursive: true);
              }
              await targetFile.writeAsBytes(response.data!, flush: false);
            }
          } catch (e) {
            // Ignore single tile fetch error
          }

          completed++;
          _downloadProgress = completed / totalTiles;
          _downloadStatus = 'Downloading $completed / $totalTiles tiles (${(_downloadProgress * 100).toInt()}%)...';
          notifyListeners();

          // Polite throttle to prevent OSM rate-limiting
          await Future.delayed(const Duration(milliseconds: 35));
        }
      }

      final workers = List.generate(poolSize, (_) => worker());
      await Future.wait(workers);

      _downloadProgress = 1.0;
      _downloadStatus = 'Successfully cached $areaName for offline use!';
      _cachedAreaName = areaName;
      _lastCachedAt = DateTime.now();
      await _calculateStorageStats();
    } catch (e) {
      _downloadStatus = 'Error downloading zone map: $e';
      debugPrint('[OfflineMapService] Download error: $e');
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Delete all cached map tiles from storage to free space
  Future<void> clearCache() async {
    try {
      if (_tilesDir != null && await _tilesDir!.exists()) {
        await _tilesDir!.delete(recursive: true);
        await _tilesDir!.create(recursive: true);
      }
      _cachedTilesCount = 0;
      _cachedSizeMb = 0.0;
      notifyListeners();
      debugPrint('[OfflineMapService] Cleared cached tiles');
    } catch (e) {
      debugPrint('[OfflineMapService] Error clearing cache: $e');
    }
  }

  // ─── Slippy Map Tile Coordinate Mathematics ────────────────────────────────

  static int _lon2tileX(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  static int _lat2tileY(double lat, int z) {
    final rad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0 * (1 << z)).floor();
  }
}
