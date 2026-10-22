import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/safety_service.dart';
import '../services/offline_map_service.dart';
import '../models/safety_models.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late MapController _mapController;
  final TextEditingController _searchController = TextEditingController();
  bool _showHeatmap = true;
  bool _showSafePlaces = true;
  bool _showReports = false;
  SafePlace? _selectedPlace;
  SafetyService? _safetyService;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    
    // Listen for trip changes to center camera
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _safetyService = context.read<SafetyService>();
        _safetyService?.addListener(_handleTripChange);
      }
    });
  }

  void _handleTripChange() {
    if (!mounted || _safetyService == null) return;
    if (_safetyService!.isTripActive) {
      _mapController.move(LatLng(_safetyService!.currentLat, _safetyService!.currentLng), 15);
    }
  }

  @override
  void dispose() {
    _safetyService?.removeListener(_handleTripChange);
    _mapController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SafetyService>();
    final offlineMap = context.watch<OfflineMapService>();

    // Seamlessly load cached zones from local disk when offline or in low network
    final hotspots = offlineMap.cachedHotspots.isNotEmpty
        ? offlineMap.cachedHotspots
        : SafetyModels.getCrimeHotspots();
    final safePlaces = service.safePlaces.isNotEmpty
        ? service.safePlaces
        : (offlineMap.cachedSafePlaces.isNotEmpty
            ? offlineMap.cachedSafePlaces
            : SafetyModels.getSafePlaces());

    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(service.currentLat, service.currentLng),
              initialZoom: 13,
              maxZoom: 18,
              minZoom: 10,
              onTap: (_, __) {
                setState(() => _selectedPlace = null);
              },
            ),
            children: [
              // OpenStreetMap Standard with seamless offline disk tile caching
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.safeher.safeher',
                tileProvider: offlineMap.tileProvider,
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors',
                    onTap: () => _launchOSM(),
                  ),
                ],
              ),

              // Crime zones (Red Zones) from SafetyService / Offline Cache
              if (_showHeatmap)
                PolygonLayer(
                  polygons: hotspots
                      .where((h) => h.boundary != null)
                      .map((h) => Polygon(
                              points: h.boundary!,
                            color: AppTheme.dangerRed.withValues(alpha: 0.5),
                            borderStrokeWidth: 3,
                            borderColor: AppTheme.dangerRed,
                            isFilled: true,
                          ))
                      .toList(),
                ),

              if (_showHeatmap)
                CircleLayer(
                  circles: hotspots
                      .where((h) => h.boundary == null)
                      .map((hotspot) {
                    return CircleMarker(
                      point: LatLng(hotspot.lat, hotspot.lng),
                      radius: 400, // 400m radius matching backend
                      useRadiusInMeter: true,
                      color: AppTheme.dangerRed.withValues(alpha: 0.4),
                      borderColor: AppTheme.dangerRed.withValues(alpha: 0.6),
                      borderStrokeWidth: 2,
                    );
                  }).toList(),
                ),

              // Safe places markers (from Overpass / Offline Cache)
              if (_showSafePlaces)
                MarkerLayer(
                  markers: safePlaces.map((place) {
                    final isSelected = _selectedPlace == place;
                    return Marker(
                      point: LatLng(place.lat, place.lng),
                      width: isSelected ? 50 : 40,
                      height: isSelected ? 50 : 40,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPlace = place),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _getPlaceColor(place.type),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _getPlaceColor(place.type).withValues(alpha: 0.5),
                                blurRadius: isSelected ? 15 : 8,
                                spreadRadius: isSelected ? 3 : 1,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              place.typeEmoji,
                              style: TextStyle(fontSize: isSelected ? 20 : 16),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // Community reports
              if (_showReports)
                MarkerLayer(
                  markers: service.communityReports.map((report) {
                    return Marker(
                      point: LatLng(report.lat, report.lng),
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.cautionYellow.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Center(
                          child: Icon(Icons.report_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              // Safest Path Polyline
              if (service.isTripActive && service.currentTrip != null && service.currentTrip!.path.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: service.currentTrip!.path,
                      color: AppTheme.safeGreen,
                      strokeWidth: 5,
                      isDotted: false,
                    ),
                  ],
                ),

              // Current location marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(service.currentLat, service.currentLng),
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryPurple.withValues(alpha: 0.5),
                            blurRadius: 15,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.person_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Navigation Overlay (Top)
          if (service.isTripActive && service.currentInstruction != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: Column(
                children: [
                    // Route Status (Verified Safe Path Badge)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.safeGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.safeGreen.withValues(alpha: 0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.safeGreen.withValues(alpha: 0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.safeGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 10),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SAFEST ROUTE ACTIVE',
                          style: TextStyle(
                            color: AppTheme.safeGreen, 
                            fontWeight: FontWeight.w900, 
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                   // Danger/Off-route Alert
                  if (service.dangerZoneAlert || (service.currentTrip?.isOffRoute ?? false))
                    _buildNavAlert(service),
                  
                  const SizedBox(height: 8),

                  // Instruction Card
                  _buildInstructionCard(service),
                ],
              ),
            ),

          // Top overlay (Search & Filters) - Hide during active navigation
          if (!service.isTripActive)
            Positioned(
              top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.darkBg.withValues(alpha: 0.95),
                    AppTheme.darkBg.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Search bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: AppTheme.glassDecoration(opacity: 0.12, borderRadius: 16),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search safe routes & places...',
                              hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (value) => _handleSearch(value, service),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _handleSearch(_searchController.text, service),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryPurple.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.tune_rounded, color: AppTheme.primaryPurple, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'Crime Zones',
                          icon: Icons.warning_rounded,
                          isActive: _showHeatmap,
                          color: AppTheme.dangerRed,
                          onTap: () => setState(() => _showHeatmap = !_showHeatmap),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Safe Places',
                          icon: Icons.shield_rounded,
                          isActive: _showSafePlaces,
                          color: AppTheme.safeGreen,
                          onTap: () => setState(() => _showSafePlaces = !_showSafePlaces),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Reports',
                          icon: Icons.flag_rounded,
                          isActive: _showReports,
                          color: AppTheme.cautionYellow,
                          onTap: () => setState(() => _showReports = !_showReports),
                        ),
                      ],
                    ),
                  ),

                  // Offline Mode Banner Indicator
                  if (offlineMap.isOffline) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.cautionYellow.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.cautionYellow.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.cautionYellow,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'OFFLINE MAP ACTIVE • ${offlineMap.cachedTilesCount} TILES & ${hotspots.length + safePlaces.length} ZONES LOADED',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                color: AppTheme.cautionYellow,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Selected place detail
          if (_selectedPlace != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: _buildPlaceDetail(_selectedPlace!),
            ),

          // Map controls
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 160,
            child: Column(
              children: [
                _MapButton(
                  icon: Icons.my_location_rounded,
                  onTap: () async {
                    await service.fetchLiveLocation();
                    _mapController.move(
                      LatLng(service.currentLat, service.currentLng),
                      15,
                    );
                  },
                ),
                const SizedBox(height: 8),
                // Offline Map & Zone Manager Button
                _MapButton(
                  icon: offlineMap.isOffline
                      ? Icons.cloud_off_rounded
                      : (offlineMap.isDownloading ? Icons.downloading_rounded : Icons.offline_pin_rounded),
                  iconColor: offlineMap.isOffline
                      ? AppTheme.cautionYellow
                      : (offlineMap.isDownloading ? AppTheme.accentCyan : AppTheme.safeGreen),
                  badge: offlineMap.isDownloading
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accentCyan,
                          ),
                        )
                      : null,
                  onTap: () => _showOfflineMapManager(context, offlineMap, service),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.location_city_rounded,
                  onTap: () {
                    // Quick jump to Nagpur (Sitabuldi) for testing geofencing
                    _mapController.move(const LatLng(21.1458, 79.0882), 14);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📍 Centered on Nagpur Red Zones'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.add_rounded,
                  onTap: () {
                    final zoom = _mapController.camera.zoom + 1;
                    _mapController.move(_mapController.camera.center, zoom);
                  },
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.remove_rounded,
                  onTap: () {
                    final zoom = _mapController.camera.zoom - 1;
                    _mapController.move(_mapController.camera.center, zoom);
                  },
                ),
              ],
            ),
          ),

          // Risk indicator
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 160,
            child: _buildRiskIndicator(service),
          ),
        ],
      ),
    );
  }

  void _handleSearch(String query, SafetyService service) {
    if (query.isEmpty) return;
    
    final place = service.searchPlace(query);
    if (place != null) {
      setState(() {
        _selectedPlace = place;
        _showSafePlaces = true; // Ensure markers are visible
      });
      _mapController.move(LatLng(place.lat, place.lng), 15);
      
      // Close keyboard
      FocusScope.of(context).unfocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No safe place found matching "$query"'),
          backgroundColor: AppTheme.dangerRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildPlaceDetail(SafePlace place) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _getPlaceColor(place.type).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(place.typeEmoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getPlaceColor(place.type).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        place.typeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: _getPlaceColor(place.type),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.star_rounded, size: 14, color: AppTheme.cautionYellow),
                    const SizedBox(width: 2),
                    Text(
                      place.rating.toString(),
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              // Show quick feedback
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🗺️ Calculating safest route to ${place.name}...'),
                  backgroundColor: AppTheme.primaryPurple,
                  duration: const Duration(seconds: 2),
                ),
              );
              
              // Pass exact coordinates to bypass flaky geocoding for known places
              final error = await context.read<SafetyService>().startTrip("${place.lat},${place.lng}");
              
              if (mounted) {
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('⚠️ Route Error: $error'),
                      backgroundColor: AppTheme.dangerRed,
                    ),
                  );
                } else {
                  // Stay on map, but close the place detail card to show navigation
                  setState(() => _selectedPlace = null);
                }
              }
            },
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.navigation_rounded, color: AppTheme.primaryPurple, size: 20),
                ),
                const SizedBox(height: 4),
                Text('Navigate', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskIndicator(SafetyService service) {
    Color riskColor;
    if (service.riskScore <= 25) {
      riskColor = AppTheme.safeGreen;
    } else if (service.riskScore <= 50) {
      riskColor = AppTheme.cautionYellow;
    } else if (service.riskScore <= 75) {
      riskColor = AppTheme.dangerOrange;
    } else {
      riskColor = AppTheme.dangerRed;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: riskColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${service.riskScore}',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: riskColor,
            ),
          ),
          Text(
            'Risk',
            style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Color _getPlaceColor(SafePlaceType type) {
    switch (type) {
      case SafePlaceType.policeStation:
        return AppTheme.accentBlue;
      case SafePlaceType.hospital:
        return AppTheme.safeGreen;
      case SafePlaceType.safeZone:
        return AppTheme.primaryPurple;
    }
  }

  Future<void> _launchOSM() async {
    final Uri url = Uri.parse('https://www.openstreetmap.org/copyright');
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  Widget _buildNavAlert(SafetyService service) {
    final isOffRoute = service.currentTrip?.isOffRoute ?? false;
    final color = isOffRoute ? AppTheme.dangerOrange : AppTheme.dangerRed;
    final icon = isOffRoute ? Icons.alt_route_rounded : Icons.warning_rounded;
    final text = isOffRoute 
        ? 'OFF-ROUTE: Return to safe path' 
        : 'DANGER ZONE: ${service.dangerZoneName.toUpperCase()}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white, 
                fontWeight: FontWeight.w900, 
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard(SafetyService service) {
    final inst = service.currentInstruction!;
    final isSafe = inst.isSafeZone;
    final accentColor = isSafe ? AppTheme.safeGreen : AppTheme.dangerOrange;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(2), // Gradient border effect
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryPurple.withValues(alpha: 0.5),
              Colors.transparent,
              AppTheme.primaryPurple.withValues(alpha: 0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E3F).withValues(alpha: 0.9), // Deep midnight blue/purple
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              // Direction Icon with Glow
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.1),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(inst.icon, color: accentColor, size: 32),
              ),
              const SizedBox(width: 20),
              
              // Instruction Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      inst.instruction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.safeGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            service.distanceToNextTurnM < 1000 
                              ? '${service.distanceToNextTurnM.toStringAsFixed(0)}m turn'
                              : '${(service.distanceToNextTurnM / 1000).toStringAsFixed(1)}km turn',
                            style: const TextStyle(
                              color: AppTheme.safeGreen, 
                              fontSize: 11, 
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${service.etaMinutes} min • ${service.distanceRemainingKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            color: AppTheme.textMuted, 
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Close/End Trip
              GestureDetector(
                onTap: () => service.endTrip(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.close_rounded, color: AppTheme.dangerRed, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOfflineMapManager(
    BuildContext context,
    OfflineMapService offlineMap,
    SafetyService service,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final mapService = modalContext.watch<OfflineMapService>();

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 25,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (mapService.isOffline ? AppTheme.cautionYellow : AppTheme.safeGreen).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          mapService.isOffline ? Icons.cloud_off_rounded : Icons.offline_pin_rounded,
                          color: mapService.isOffline ? AppTheme.cautionYellow : AppTheme.safeGreen,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Offline Map & Safe Zones',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mapService.isOffline
                                  ? 'Offline / Low Network Mode Active'
                                  : 'Cache local zones so the map works in dead zones',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Cache Status Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Cached Storage',
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${mapService.cachedTilesCount} tiles (${mapService.cachedSizeMb.toStringAsFixed(2)} MB)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Protected Zones',
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${mapService.cachedHotspots.length} Red Zones • ${mapService.cachedSafePlaces.length} Safe Havens',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.safeGreen,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Current Active Zone',
                              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54),
                            ),
                            Flexible(
                              child: Text(
                                mapService.cachedAreaName,
                                textAlign: TextAlign.end,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentCyan,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Live Downloading Progress Indicator
                  if (mapService.isDownloading) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Caching Map Tiles & Zones...',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                '${(mapService.downloadProgress * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryPurple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: mapService.downloadProgress > 0 ? mapService.downloadProgress : null,
                            backgroundColor: AppTheme.primaryPurple.withValues(alpha: 0.15),
                            valueColor: const AlwaysStoppedAnimation(AppTheme.primaryPurple),
                            borderRadius: BorderRadius.circular(6),
                            minHeight: 6,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            mapService.downloadStatus,
                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  Text(
                    'DOWNLOAD ZONES (WHILE IN RANGE)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Download 1: Current GPS Location (5km)
                  _buildZoneDownloadTile(
                    title: 'Current Location Zone (5 km)',
                    subtitle: 'Caches current area tiles & nearby police/hospital safe zones',
                    icon: Icons.my_location_rounded,
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Downloading offline map for your current zone...'),
                          backgroundColor: AppTheme.safeGreen,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      await mapService.downloadZoneMap(
                        centerLat: service.currentLat != 0.0 ? service.currentLat : 19.9975,
                        centerLng: service.currentLng != 0.0 ? service.currentLng : 73.7898,
                        radiusKm: 5.0,
                        areaName: 'Current GPS Zone',
                        hotspots: SafetyModels.getCrimeHotspots(),
                        safePlaces: service.safePlaces,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // Download 2: Nashik City Zone
                  _buildZoneDownloadTile(
                    title: 'Nashik Metropolitan Zone',
                    subtitle: 'Full coverage for College Road, Gangapur, CBS, Dwarka & Panchavati',
                    icon: Icons.location_city_rounded,
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Preloading Nashik City offline map...'),
                          backgroundColor: AppTheme.safeGreen,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      await mapService.downloadZoneMap(
                        centerLat: 19.9975,
                        centerLng: 73.7898,
                        radiusKm: 8.0,
                        areaName: 'Nashik Metropolitan Zone',
                        hotspots: SafetyModels.getCrimeHotspots(),
                        safePlaces: service.safePlaces,
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // Download 3: Nagpur Metro Zone
                  _buildZoneDownloadTile(
                    title: 'Nagpur Central & Sitabuldi Zone',
                    subtitle: 'Full coverage for Sitabuldi, Itwari, Sadar & Nagpur Railway Station',
                    icon: Icons.map_rounded,
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Preloading Nagpur Metro offline map...'),
                          backgroundColor: AppTheme.safeGreen,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      await mapService.downloadZoneMap(
                        centerLat: 21.1458,
                        centerLng: 79.0882,
                        radiusKm: 8.0,
                        areaName: 'Nagpur Metro & Sitabuldi Zone',
                        hotspots: SafetyModels.getCrimeHotspots(),
                        safePlaces: service.safePlaces,
                      );
                    },
                  ),

                  const SizedBox(height: 14),
                  // Clear Cache Button
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await mapService.clearCache();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Offline map cache cleared.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.dangerRed),
                      label: const Text(
                        'Clear Offline Map Cache',
                        style: TextStyle(color: AppTheme.dangerRed, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
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

  Widget _buildZoneDownloadTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.primaryPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.download_rounded, size: 18, color: AppTheme.accentCyan),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? color : AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? color : AppTheme.textMuted,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final Widget? badge;

  const _MapButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.darkSurface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: iconColor ?? AppTheme.textPrimary, size: 20),
          ),
          if (badge != null)
            Positioned(
              top: -2,
              right: -2,
              child: badge!,
            ),
        ],
      ),
    );
  }
}

