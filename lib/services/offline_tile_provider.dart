import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_map_service.dart';

/// Custom [TileProvider] that prioritizes offline cached map tiles stored locally
/// on the device. When offline or in low-network areas, tiles are served instantly
/// from local disk. When online, tiles are fetched and automatically stored for offline use.
class OfflineTileProvider extends TileProvider {
  final OfflineMapService offlineMapService;

  static final Uint8List transparentTile = Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0,
    0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, 84, 120,
    156, 99, 96, 0, 0, 0, 2, 0, 1, 229, 39, 222, 250, 0, 0, 0, 0, 73, 69, 78,
    68, 174, 66, 96, 130
  ]);

  OfflineTileProvider({
    required this.offlineMapService,
    super.headers,
  });

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = offlineMapService.getTileFile(coordinates.z, coordinates.x, coordinates.y);
    final url = getTileUrl(coordinates, options);

    return OfflineCachedTileImageProvider(
      url: url,
      file: file,
      headers: headers,
      isOffline: offlineMapService.isOffline,
      onTileCached: () => offlineMapService.onTileAdded(),
    );
  }
}

/// Dedicated [ImageProvider] that resolves tiles from device file storage or network
@immutable
class OfflineCachedTileImageProvider extends ImageProvider<OfflineCachedTileImageProvider> {
  final String url;
  final File file;
  final Map<String, String> headers;
  final bool isOffline;
  final VoidCallback? onTileCached;

  const OfflineCachedTileImageProvider({
    required this.url,
    required this.file,
    this.headers = const {},
    this.isOffline = false,
    this.onTileCached,
  });

  @override
  ImageStreamCompleter loadImage(OfflineCachedTileImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _loadAsync(OfflineCachedTileImageProvider key, ImageDecoderCallback decode) async {
    // 1. Check local file on disk first
    if (file.existsSync()) {
      try {
        final length = file.lengthSync();
        if (length > 0) {
          final bytes = await file.readAsBytes();
          final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
          return await decode(buffer);
        }
      } catch (e) {
        debugPrint('[OfflineTileProvider] Error reading cached tile: $e');
      }
    }

    // 2. If completely offline or in zero-reception zone, use transparent tile to prevent crashes
    if (isOffline) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(OfflineTileProvider.transparentTile);
      return decode(buffer);
    }

    // 3. User is in range (online): fetch tile and cache locally
    try {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'User-Agent': 'NivaranSafetyApp/1.0 (Offline Map Caching)',
            ...headers,
          },
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
        final bytes = Uint8List.fromList(response.data!);
        // Save to offline storage in background
        file.parent.create(recursive: true).then((_) async {
          await file.writeAsBytes(bytes, flush: false);
          onTileCached?.call();
        }).catchError((err) {
          debugPrint('[OfflineTileProvider] Tile write error: $err');
        });

        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return await decode(buffer);
      }
    } catch (_) {
      // Network timeout / connection dropped in dead spot
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(OfflineTileProvider.transparentTile);
    return decode(buffer);
  }

  @override
  Future<OfflineCachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<OfflineCachedTileImageProvider>(this);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OfflineCachedTileImageProvider && other.url == url && other.file.path == file.path;
  }

  @override
  int get hashCode => Object.hash(url, file.path);
}
