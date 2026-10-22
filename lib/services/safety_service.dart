import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/safety_models.dart';
import 'blockchain_service.dart';
import 'supabase_service.dart';
import 'package:dio/dio.dart' as dio;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'weather_service.dart';
import 'package:another_telephony/telephony.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'mesh_service.dart';
import '../models/mesh_message.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:screen_state/screen_state.dart';
import 'night_mode_service.dart';
import 'package:hive/hive.dart';
import 'local_storage_service.dart';
import 'offline_map_service.dart';

class SafetyService extends ChangeNotifier {
  static late SafetyService instance;

  // Current user location (simulated for demo)
  double _currentLat = 0.0;
  double _currentLng = 0.0;
  bool _isSOSActive = false;
  bool _isTripActive = false;
  bool _isFakeCallActive = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isAICompanionActive = false;
  
  // SOS Trigger States
  bool _voiceTriggerEnabled = false; // Disabled by default to prevent automatic recording 
  bool _powerTriggerEnabled = true;

  // Location Sharing Toggles
  bool _continuousTrackingEnabled = false;
  bool _sosAutoShareEnabled = true;
  bool _tripSharingEnabled = true;
  Timer? _continuousShareTimer;
  
  bool get continuousTrackingEnabled => _continuousTrackingEnabled;
  bool get sosAutoShareEnabled => _sosAutoShareEnabled;
  bool get tripSharingEnabled => _tripSharingEnabled;
  
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final Screen _screen = Screen();

  DateTime? _lastScreenEvent;
  int _screenToggleCount = 0;
  
  bool get voiceTriggerEnabled => _voiceTriggerEnabled;
  bool get powerTriggerEnabled => _powerTriggerEnabled;

  int _riskScore = 32;
  String _riskLevel = 'Moderate';
  Timer? _locationTimer;
  Timer? _riskTimer;
  Timer? _anomalyTimer;
  
  final List<EmergencyContact> _emergencyContacts = [];

  // Community Reports & Dynamic Safe Places
  final List<SafetyReport> _communityReports = [];
  final List<SafePlace> _safePlaces = SafetyModels.getSafePlaces();
  bool _fetchedDynamicPlaces = false;

  final List<String> _sosLog = [];
  TripSession? _currentTrip;
  RiskAssessment? _currentRiskAssessment;
  
  // Anomaly detection state
  bool _anomalyDetected = false;
  String _anomalyType = '';
  int _currentInstructionIndex = 0;
  bool _dangerZoneAlert = false;
  String _dangerZoneName = '';
  double _currentSpeedKmh = 0;
  double _distanceRemainingKm = 0;
  int _etaMinutes = 0;
  double _distanceToNextTurnM = 0;
  
  // Getters
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  bool get isSOSActive => _isSOSActive;
  bool get isTripActive => _isTripActive;
  bool get isFakeCallActive => _isFakeCallActive;
  bool get isAICompanionActive => _isAICompanionActive;
  int get riskScore => _riskScore;
  String get riskLevel => _riskLevel;
  List<EmergencyContact> get emergencyContacts => _emergencyContacts;
  List<SafetyReport> get communityReports => _communityReports;
  List<SafePlace> get safePlaces => _safePlaces;
  List<String> get sosLog => _sosLog;
  TripSession? get currentTrip => _currentTrip;
  RiskAssessment? get currentRiskAssessment => _currentRiskAssessment;
  bool get anomalyDetected => _anomalyDetected;
  String get anomalyType => _anomalyType;
  int get currentInstructionIndex => _currentInstructionIndex;
  bool get dangerZoneAlert => _dangerZoneAlert;
  String get dangerZoneName => _dangerZoneName;
  
  NavigationInstruction? get currentInstruction {
    if (_currentTrip == null || _currentTrip!.instructions.isEmpty) return null;
    if (_currentInstructionIndex >= _currentTrip!.instructions.length) return null;
    return _currentTrip!.instructions[_currentInstructionIndex];
  }

  double get currentSpeedKmh => _currentSpeedKmh;
  double get distanceRemainingKm => _distanceRemainingKm;
  int get etaMinutes => _etaMinutes;
  double get distanceToNextTurnM => _distanceToNextTurnM;

  BlockchainService? _blockchainService;
  WeatherService? _weatherService;
  MeshService? _meshService;
  
  void updateBlockchainService(BlockchainService? service) {
    _blockchainService = service;
  }

  void updateWeatherService(WeatherService? service) {
    if (_weatherService == service || service == null) return;
    _weatherService = service;
    if (_currentLat != 0.0 && _lastWeatherUpdate == null) {
      _weatherService!.fetchWeather(_currentLat, _currentLng);
      _lastWeatherUpdate = DateTime.now();
    }
  }
  
  void updateMeshService(MeshService? service) {
    _meshService = service;
  }

  OfflineMapService? _offlineMapService;

  void updateOfflineMapService(OfflineMapService? service) {
    if (_offlineMapService == service || service == null) return;
    _offlineMapService = service;
    if (_safePlaces.isEmpty && service.cachedSafePlaces.isNotEmpty) {
      _safePlaces.clear();
      _safePlaces.addAll(service.cachedSafePlaces);
      notifyListeners();
    }
  }

  Future<void> cacheCurrentZoneMap({double radiusKm = 5.0, String? areaName}) async {
    if (_offlineMapService == null) return;
    await _offlineMapService!.downloadZoneMap(
      centerLat: _currentLat != 0.0 ? _currentLat : 19.9975,
      centerLng: _currentLng != 0.0 ? _currentLng : 73.7898,
      radiusKm: radiusKm,
      areaName: areaName ?? 'Current Location Zone',
      hotspots: SafetyModels.getCrimeHotspots(),
      safePlaces: _safePlaces,
    );
  }

  String? _userName;
  String? _userEmail;
  String? _currentSOSId; 
  DateTime? _lastDbLocationUpdate;
  DateTime? _lastWeatherUpdate;
  void updateUserContext(String name, String email) {
    if (_userEmail == email && (_userName == name || name.isEmpty)) return;
    if (name.isNotEmpty) _userName = name;
    _userEmail = email;
    fetchContacts(); // Fetch contacts whenever user context changes
    
    // If name is still missing but we have email, try a quick fetch from Supabase
    if ((_userName == null || _userName!.isEmpty || _userName == 'Unknown User') && _userEmail != null) {
      Supabase.instance.client
          .from('users')
          .select('name')
          .eq('email', _userEmail!)
          .maybeSingle()
          .then((data) {
        if (data != null && data['name'] != null) {
          _userName = data['name'];
          notifyListeners();
        }
      });
    }
    
    // Initialize triggers
    _initVoiceTrigger();
    _initPowerButtonTrigger();
  }

  void toggleVoiceTrigger(bool enabled) {
    _voiceTriggerEnabled = enabled;
    if (enabled) {
      _startVoiceListening();
    } else {
      _speechToText.stop();
    }
    notifyListeners();
  }

  void togglePowerTrigger(bool enabled) {
    _powerTriggerEnabled = enabled;
    notifyListeners();
  }

  Future<void> _initVoiceTrigger() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (_voiceTriggerEnabled && !_isSOSActive) {
            _startVoiceListening(); // Keep listening
          }
        }
      },
      onError: (error) => debugPrint('Speech Error: $error'),
    );
    if (available && _voiceTriggerEnabled) {
      _startVoiceListening();
    }
  }

  void _startVoiceListening() {
    if (!_voiceTriggerEnabled || _isSOSActive) return;
    _speechToText.listen(
      onResult: (result) {
        String spoke = result.recognizedWords.toLowerCase();
        if (spoke.contains('help') || spoke.contains('emergency') || spoke.contains('danger')) {
          debugPrint('Voice trigger detected: $spoke. Activating SOS...');
          activateSOS();
        }
      },
    );
  }

  void _initPowerButtonTrigger() {
    _screen.screenStateStream.listen((event) {
      if (!_powerTriggerEnabled || _isSOSActive) return;
      
      final now = DateTime.now();
      if (_lastScreenEvent == null || now.difference(_lastScreenEvent!).inSeconds > 5) {
        _screenToggleCount = 1;
      } else {
        _screenToggleCount++;
      }
      _lastScreenEvent = now;

      debugPrint('Screen toggle count: $_screenToggleCount');
      if (_screenToggleCount >= 5) { // 5 toggles roughly equals 3 power presses (on-off-on-off-on)
        debugPrint('Power button sequence detected! Activating SOS...');
        activateSOS();
        _screenToggleCount = 0;
      }
    });
  }

  Future<void> fetchContacts() async {
    if (_userEmail == null) {
      debugPrint('Skipping fetchContacts: No userEmail set');
      return;
    }
    
    debugPrint('Fetching emergency contacts for: $_userEmail');
    try {
      final List<dynamic> data = await Supabase.instance.client
          .from('contacts')
          .select()
          .eq('user_email', _userEmail!);

      debugPrint('Supabase: Found ${data.length} emergency contacts');
      _emergencyContacts.clear();
      for (var item in data) {
        _emergencyContacts.add(EmergencyContact(
          id: item['id'].toString(),
          name: item['name'] ?? 'Unknown',
          phone: item['phone'] ?? '',
          relationship: item['relation'] ?? 'Family',
          isPrimary: _emergencyContacts.isEmpty,
        ));
      }
      
      if (_emergencyContacts.isNotEmpty) {
        _sosLog.insert(0, '📋 Loaded ${_emergencyContacts.length} trusted contacts');
        _saveCachedContacts();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Supabase Error (fetchContacts, trying local cache): $e');
      _loadCachedContacts();
    }
  }

  void _saveCachedContacts() {
    try {
      if (_userEmail == null) return;
      final box = Hive.box(LocalStorageService.settingsBoxName);
      final list = _emergencyContacts.map((c) => {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'relation': c.relationship,
        'isPrimary': c.isPrimary,
      }).toList();
      box.put('cached_contacts_$_userEmail', list);
    } catch (_) {}
  }

  void _loadCachedContacts() {
    try {
      if (_userEmail == null) return;
      final box = Hive.box(LocalStorageService.settingsBoxName);
      final raw = box.get('cached_contacts_$_userEmail');
      if (raw != null && raw is List) {
        _emergencyContacts.clear();
        for (var item in raw) {
          final map = Map<String, dynamic>.from(item);
          _emergencyContacts.add(EmergencyContact(
            id: map['id']?.toString() ?? '',
            name: map['name'] ?? 'Contact',
            phone: map['phone'] ?? '',
            relationship: map['relation'] ?? 'Family',
            isPrimary: map['isPrimary'] ?? false,
          ));
        }
        if (_emergencyContacts.isNotEmpty) {
          _sosLog.insert(0, '📋 Loaded ${_emergencyContacts.length} offline cached contacts');
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  SafetyService() {
    instance = this;
    _initializeService();
    fetchCommunityReports();
  }

  void _initializeService() {
    // Start real GPS location stream
    _startRealGPS();

    // Subscribe to real-time incidents
    _subscribeToIncidents();

    // Update risk assessment periodically
    _riskTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _updateRiskAssessment();
    });

    // Initial risk assessment
    _updateRiskAssessment();
  }

  StreamSubscription<Position>? _positionStream;

  Future<void> _startRealGPS() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled, using default coords');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever');
        return;
      }

      // Get initial position immediately
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
      );
      updateLocation(pos.latitude, pos.longitude);

      // Then stream continuous updates
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, // 'best' sometimes hangs indoors
          distanceFilter: 10, // 10 meters is enough for safety triggers
        ),
      ).listen((Position position) {
        // Use updateLocation to trigger all side effects (risk, divergence, live tracking)
        updateLocation(position.latitude, position.longitude);
        
        // Update speed and nav stats which are trip-specific
        _currentSpeedKmh = (position.speed >= 0) ? position.speed * 3.6 : 0;
        _updateNavStats();
        
        if (_isTripActive && _currentTrip != null && _currentTrip!.instructions.isNotEmpty) {
          final nextIdx = _currentInstructionIndex + 1;
          if (nextIdx < _currentTrip!.path.length) {
            final nextPt = _currentTrip!.path[nextIdx];
            final dist = calculateDistance(_currentLat, _currentLng, nextPt.latitude, nextPt.longitude);
            if (dist < 0.03) { // within 30m
              _currentInstructionIndex = nextIdx;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('GPS stream error: $e');
    }
  }

  Future<void> fetchCommunityReports() async {
    try {
      final data = await Supabase.instance.client
          .from('incidents')
          .select()
          .order('created_at', ascending: false);

      _communityReports.clear();
      for (var item in data) {
        _communityReports.add(_mapToSafetyReport(item));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Supabase Error (fetchCommunityReports): $e');
    }
  }

  SafetyReport _mapToSafetyReport(Map<String, dynamic> item) {
    return SafetyReport(
      id: item['id'].toString(),
      userId: item['source'] ?? 'system',
      lat: (item['lat'] as num).toDouble(),
      lng: (item['lng'] as num).toDouble(),
      type: item['type'] != null ? _capitalize(item['type']) : 'Unknown',
      description: item['description'] ?? '',
      timestamp: DateTime.parse(item['created_at']),
      upvotes: item['risk_score'] ?? 0,
      isVerified: item['verified'] ?? false,
    );
  }

  void _subscribeToIncidents() {
    Supabase.instance.client
        .channel('public:incidents')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incidents',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty) {
              final newReport = _mapToSafetyReport(payload.newRecord);
              
              // Handle Insert
              if (payload.eventType == PostgresChangeEvent.insert) {
                // To avoid duplication with optimistic updates, check if ID exists
                if (!_communityReports.any((r) => r.id == newReport.id)) {
                  _communityReports.insert(0, newReport);
                }
              } 
              // Handle Update (verification)
              else if (payload.eventType == PostgresChangeEvent.update) {
                final idx = _communityReports.indexWhere((r) => r.id == newReport.id);
                if (idx != -1) {
                  _communityReports[idx] = newReport;
                }
              }
              notifyListeners();
            }
          },
        )
        .subscribe();
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();


  void _checkDangerZones() {
    final hotspots = SafetyModels.getCrimeHotspots();
    bool foundDanger = false;
    for (var hotspot in hotspots) {
      double dist = calculateDistance(_currentLat, _currentLng, hotspot.lat, hotspot.lng);
      if (dist < 0.5 && hotspot.intensity > 0.75) { // Within 500m of high risk
        _dangerZoneAlert = true;
        _dangerZoneName = hotspot.area;
        foundDanger = true;
        break;
      }
    }
    if (!foundDanger) {
      _dangerZoneAlert = false;
      _dangerZoneName = '';
    }
  }

  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lng2 - lng1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }

  /// Returns a list of safe places sorted by proximity to current location.
  List<SafePlace> getNearestSafePlaces({SafePlaceType? type, int limit = 3}) {
    if (_safePlaces.isEmpty) return [];
    
    final list = type == null 
        ? List<SafePlace>.from(_safePlaces)
        : _safePlaces.where((p) => p.type == type).toList();
    
    list.sort((a, b) {
      final distA = calculateDistance(_currentLat, _currentLng, a.lat, a.lng);
      final distB = calculateDistance(_currentLat, _currentLng, b.lat, b.lng);
      return distA.compareTo(distB);
    });
    
    return list.take(limit).toList();
  }

  void _updateNavStats() {
    if (!_isTripActive || _currentTrip == null || _currentTrip!.path.isEmpty) {
      _distanceRemainingKm = 0;
      _etaMinutes = 0;
      _distanceToNextTurnM = 0;
      return;
    }

    final path = _currentTrip!.path;
    // Find the closest waypoint index on the route
    int closestIdx = 0;
    double closestDist = double.infinity;
    for (int i = 0; i < path.length; i++) {
      final d = calculateDistance(_currentLat, _currentLng, path[i].latitude, path[i].longitude);
      if (d < closestDist) {
        closestDist = d;
        closestIdx = i;
      }
    }

    // Sum remaining path distance from closest waypoint to destination
    double remaining = 0;
    for (int i = closestIdx; i < path.length - 1; i++) {
      remaining += calculateDistance(
        path[i].latitude, path[i].longitude,
        path[i + 1].latitude, path[i + 1].longitude,
      );
    }
    _distanceRemainingKm = remaining;

    // ETA: remaining_km / speed_km_h * 60, fallback 50 km/h average
    final speed = _currentSpeedKmh > 3 ? _currentSpeedKmh : 50.0;
    _etaMinutes = remaining > 0 ? (remaining / speed * 60).round() : 0;

    // Distance to next turn: use the instruction index waypoint in path
    final nextTurnIdx = _currentInstructionIndex + 1;
    if (nextTurnIdx < path.length) {
      _distanceToNextTurnM = calculateDistance(
        _currentLat, _currentLng,
        path[nextTurnIdx].latitude, path[nextTurnIdx].longitude,
      ) * 1000; // km -> m
    } else {
      _distanceToNextTurnM = 0;
    }
  }

  void _checkPathDivergence() {
    if (!_isTripActive || _currentTrip == null || _currentTrip!.path.isEmpty) return;
    
    double minDistance = double.infinity;
    for (var point in _currentTrip!.path) {
      double dist = calculateDistance(_currentLat, _currentLng, point.latitude, point.longitude);
      if (dist < minDistance) minDistance = dist;
    }
    
    // If user is more than 150m away from the path, trigger alert
    bool isDiverged = minDistance > 0.15; 
    if (isDiverged != _currentTrip!.isOffRoute) {
      _currentTrip!.isOffRoute = isDiverged;
      if (isDiverged) {
        simulateAnomaly('Route Deviation');
      }
      notifyListeners();
    }
  }


  void _updateRiskAssessment() {
    _currentRiskAssessment = RiskAssessment.calculate(
      lat: _currentLat,
      lng: _currentLng,
      time: DateTime.now(),
    );

    // Update weather if needed
    if (_weatherService != null) {
      final now = DateTime.now();
      // If never updated or > 15 mins since success
      if (_lastWeatherUpdate == null || now.difference(_lastWeatherUpdate!).inMinutes >= 15) {
        if (_currentLat != 0.0) { // Essential dynamic check
          _weatherService!.fetchWeather(_currentLat, _currentLng);
          _lastWeatherUpdate = now;
        }
      }
    }
    
    double baseScore = _currentRiskAssessment!.overallScore;
    
    // Apply Night Mode Multiplier
    final nightService = NightModeService();
    if (nightService.isNightModeActive()) {
      baseScore = nightService.calculateNightRisk(
        baseRiskScore: baseScore,
        nearbyIncidents: _communityReports.map((r) => {'type': r.type.toLowerCase()}).toList(),
        isIsolatedArea: _currentSpeedKmh < 2.0,
        hasStreetLights: true,
      );
    }
    
    _riskScore = baseScore.round().clamp(0, 100);
    _riskLevel = _getNightRiskLevelLabel(_riskScore);
    notifyListeners();

    // Async ML zone prediction — blends result when available
    _fetchMLZonePrediction(baseScore);
  }

  /// Fetches ML-powered zone risk prediction from the backend and blends it
  /// with the local risk score. Falls back silently if the service is unavailable.
  Future<void> _fetchMLZonePrediction(double localScore) async {
    try {
      final baseUrl = ApiConfig.baseUrl;

      final dioClient = dio.Dio(dio.BaseOptions(
        connectTimeout: const Duration(seconds: 180),
        receiveTimeout: const Duration(seconds: 180),
      ));

      final response = await dioClient.post(
        '$baseUrl/api/zones/predict',
        data: {
          'locations': [
            {'latitude': _currentLat, 'longitude': _currentLng}
          ],
          'time_of_day_hour': DateTime.now().hour,
          'day_of_week': DateTime.now().weekday % 7,
          'is_weekend': (DateTime.now().weekday >= 6) ? 1 : 0,
        },
      );

      if (response.data != null &&
          response.data['predictions'] != null &&
          (response.data['predictions'] as List).isNotEmpty) {
        final pred = response.data['predictions'][0];
        final mlScore = ((pred['risk_score'] ?? 0.0) as num).toDouble() * 100;

        // Blend: 60% local + 40% ML
        final blended = (localScore * 0.6 + mlScore * 0.4).round().clamp(0, 100);
        _riskScore = blended;
        _riskLevel = _getNightRiskLevelLabel(_riskScore);
        notifyListeners();
      }
    } catch (e) {
      // ML service unavailable — keep local score, no crash
      debugPrint('[ML] Zone prediction unavailable: $e');
    }
  }


  String _getNightRiskLevelLabel(int score) {
    if (score >= 75) return 'Critical';
    if (score >= 50) return 'High';
    if (score >= 25) return 'Moderate';
    return 'Low';
  }

  // SOS Functions
  void activateSOS() {
    _isSOSActive = true;
    _currentSOSId = const Uuid().v4();
    final DateTime triggerTime = DateTime.now();
    _sosLog.insert(0, '🆘 SOS Activated at ${triggerTime.toString().substring(0, 19)}');
    _sosLog.insert(0, '📍 Location shared with emergency contacts');
    _sosLog.insert(0, '📱 SMS alerts sent to all contacts');
    
    // Trigger Native Automated SMS
    sendNativeSMSAlerts();
    
    // Trigger Backend Cloud SOS (Twilio Call + Admin Notification)
    _triggerCloudSOSRelay();
    
    // Broadcast via Mesh Network so connected peers can upload it if we are offline
    _broadcastMeshSOS(triggerTime);
    
    // Start Audio Recording asynchronously
    _startSOSRecording();

    // 1. Log to Supabase IMMEDIATELY (Don't wait for blockchain)
    _performSupabaseLog(null, triggerTime);

    // 2. Log to Blockchain in background
    if (_blockchainService != null) {
      _blockchainService!.storeSOSOnBlockchain({
        'type': 'SOS_ACTIVATED',
        'timestamp': triggerTime.toUtc().toIso8601String(),
        'lat': _currentLat,
        'lng': _currentLng,
        'user_name': _userName ?? 'Unknown User',
      }).then((txHash) {
        if (txHash != null && _currentSOSId != null) {
          // Update the Supabase record with the blockchain hash if it arrives later
          Supabase.instance.client
              .from('sos_logs')
              .update({'blockchain_hash': txHash})
              .eq('id', _currentSOSId!)
              .then((_) => debugPrint('Supabase: Updated with blockchain hash'))
              .catchError((e) => debugPrint('Supabase Update Error: $e'));
        }
      });
    }
    
    notifyListeners();
  }

  void _broadcastMeshSOS(DateTime triggerTime) {
    if (_meshService == null) return;
    
    final sosPayload = jsonEncode({
      'user_email': _userEmail ?? 'unknown',
      'user_name': _userName ?? 'Unknown User',
      'latitude': _currentLat,
      'longitude': _currentLng,
      'timestamp': triggerTime.toUtc().toIso8601String(),
      'priority': 'sos',
    });
    
    final msg = MeshMessage(
      id: const Uuid().v4(),
      senderId: _meshService!.userId,
      senderName: _userName ?? 'Unknown User',
      receiverId: 'broadcast',
      payload: sosPayload,
      timestamp: triggerTime,
      type: 'sos_alert',
      ackRequired: true,
      latitude: _currentLat != 0.0 ? _currentLat : null,
      longitude: _currentLng != 0.0 ? _currentLng : null,
      priority: 'sos',
    );
    
    _meshService!.broadcastMessage(msg);
  }

  Future<bool> sendNativeSMSAlerts({
    String? customMessage,
    String? specificPhone,
    bool openMessenger = true,
  }) async {
    final Telephony telephony = Telephony.instance;
    final locationUrl = 'https://maps.google.com/?q=$_currentLat,$_currentLng';
    final message = customMessage ??
        '🚨 SOS EMERGENCY 🚨 ${_userName ?? "A user"} needs help! Live location: $locationUrl';
    
    final List<String> targetPhones = [];
    if (specificPhone != null && specificPhone.trim().isNotEmpty) {
      targetPhones.add(specificPhone.trim());
    } else {
      for (var contact in _emergencyContacts) {
        if (contact.phone.trim().isNotEmpty) {
          targetPhones.add(contact.phone.trim());
        }
      }
    }

    if (targetPhones.isEmpty) {
      debugPrint('No emergency contacts or phone to alert via SMS.');
      _sosLog.insert(0, '⚠️ No SMS recipients found.');
      notifyListeners();
      return false;
    }

    // 1. Background SMS (Silent - using telephony)
    int sentCount = 0;
    for (var phone in targetPhones) {
      try {
        await telephony.sendSms(
          to: phone,
          message: message,
        );
        sentCount++;
        debugPrint('Background SMS hit for $phone');
      } catch (e) {
        debugPrint('Background SMS Error for $phone: $e');
      }
    }

    // 2. Open Native SMS Application with recipients pre-filled as a chat group
    if (openMessenger) {
      final String recipients = targetPhones.join(',');
      final Uri smsUri = Uri(
        scheme: 'sms',
        path: recipients,
        queryParameters: {'body': message},
      );

      try {
        await launchUrl(smsUri);
        debugPrint('Native SMS app opened with recipients: $recipients');
      } catch (e) {
        debugPrint('Error launching native SMS: $e');
      }
    }
    
    _sosLog.insert(0, '✅ SMS alert sent ($sentCount background, messenger opened).');
    notifyListeners();
    return true;
  }

  Future<void> _triggerCloudSOSRelay() async {
    try {
      if (_emergencyContacts.isEmpty) return;
      
      final data = {
        'userName': _userName ?? 'Unknown User',
        'phone': 'N/A', // Could fetch from user profile if needed
        'emergencyContacts': _emergencyContacts.map((c) => {
          'name': c.name,
          'phone': c.phone,
        }).toList(),
      };

      await _dio.post(
        '$_backendUrl/api/sos/trigger',
        data: data,
      );
      debugPrint('Cloud SOS Relay Triggered');
    } catch (e) {
      debugPrint('Cloud SOS Relay Error: $e');
    }
  }

  void _performSupabaseLog(String? txHash, DateTime triggerTime) {
    String? email = _userEmail;
    if (email == null || email.isEmpty) {
      email = Supabase.instance.client.auth.currentUser?.email;
    }
    if (email == null || email.isEmpty) {
      try {
        final box = Hive.box(LocalStorageService.settingsBoxName);
        email = box.get('user_email', defaultValue: '') as String?;
      } catch (_) {}
    }
    if (email == null || email.isEmpty) {
      email = 'victim_${math.Random().nextInt(90000) + 10000}@safeher.org';
    }

    final String name = (_userName != null && _userName!.isNotEmpty)
        ? _userName!
        : (Supabase.instance.client.auth.currentUser?.userMetadata?['name'] as String? ?? 'Nivaran User');

    _sosLog.insert(0, '☁️ Syncing with Safety Cloud...');
    notifyListeners();
    
    SupabaseService.logSOSEvent(
      id: _currentSOSId,
      userEmail: email,
      userName: name,
      type: 'Crime',
      latitude: _currentLat,
      longitude: _currentLng,
      blockchainHash: txHash,
      createdAt: triggerTime,
      meshPath: _meshService != null && _meshService!.connectedPeers.isNotEmpty
          ? [name, ..._meshService!.connectedPeers.values, 'Admin Gateway']
          : ['$name (Direct Mobile)'],
      notes: 'Emergency SOS activated from NIVARAN mobile application',
    ).then((result) {
      if (result['success'] == true) {
        if (result['id'] != null) {
          _currentSOSId = result['id'];
        }
        _sosLog.insert(0, '✅ Cloud Sync Active (Live Tracking On)');
      } else {
        final error = result['error'] ?? 'Unknown Error';
        _sosLog.insert(0, '❌ Sync Failed: $error');
        debugPrint('Supabase Error: $error');
      }
      notifyListeners();
    });
  }

  void deactivateSOS() {
    _isSOSActive = false;
    _sosLog.insert(0, '✅ SOS Deactivated at ${DateTime.now().toString().substring(0, 19)}');
    final activeId = _currentSOSId;
    if (activeId != null) {
      SupabaseService.resolveSOSEvent(activeId);
    }
    notifyListeners();
    // Stop recording and upload
    _stopSOSRecordingAndUpload().then((_) {
      if (_currentSOSId == activeId) {
        _currentSOSId = null;
      }
    });
  }

  Timer? _sosRecordingTimer;
  String? _currentSOSAudioPath;

  Future<void> _startSOSRecording() async {
    try {
      if (await _audioRecorder.isRecording()) {
        try { await _audioRecorder.stop(); } catch (_) {}
      }
      
      bool hasPerm = await _audioRecorder.hasPermission();
      if (!hasPerm) {
        final status = await Permission.microphone.request();
        hasPerm = status.isGranted;
      }
      if (!hasPerm) {
        _sosLog.insert(0, '⚠️ Microphone permission required for SOS audio');
        notifyListeners();
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/sos_recording_${_currentSOSId ?? DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentSOSAudioPath = path;

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _sosLog.insert(0, '🎙️ SOS Audio recording active (Evidence capturing...)');
      notifyListeners();

      // Auto-stop after 8 seconds to deliver evidence quickly to Admin Dashboard
      _sosRecordingTimer?.cancel();
      _sosRecordingTimer = Timer(const Duration(seconds: 8), () {
        if (_isSOSActive) {
          _sosLog.insert(0, '⏱️ Audio evidence captured, uploading to Admin Dashboard...');
          _stopSOSRecordingAndUpload().then((_) {
            if (_isSOSActive) {
              _startSOSRecording();
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Audio recording error: $e');
      _sosLog.insert(0, '⚠️ Audio record error: ${e.toString().split('\n').first}');
      notifyListeners();
    }
  }

  Future<void> _stopSOSRecordingAndUpload() async {
    try {
      String? path;
      if (await _audioRecorder.isRecording()) {
        path = await _audioRecorder.stop();
      }
      path ??= _currentSOSAudioPath;

      if (path != null) {
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) {
          debugPrint('Recorded audio file not found or empty');
          return;
        }

        int retries = 0;
        while (_currentSOSId == null && retries < 15) {
          await Future.delayed(const Duration(milliseconds: 300));
          retries++;
        }
        
        final targetId = _currentSOSId ?? const Uuid().v4();
        _currentSOSId = targetId;

        _sosLog.insert(0, '🎙️ Uploading SOS audio evidence to Admin Dashboard...');
        notifyListeners();
        
        // 1. Upload to Supabase directly (stores base64 data URI in sos_logs)
        final audioUrl = await SupabaseService.uploadSOSAudio(
          logId: targetId,
          filePath: path,
        );

        // 2. Also send to Express backend
        try {
          final formData = dio.FormData.fromMap({
            'logId': targetId,
            'audio': await dio.MultipartFile.fromFile(
              path, 
              filename: '$targetId.m4a',
            ),
          });
          await _dio.post(
            '$_backendUrl/api/blockchain/sos/audio',
            data: formData,
          );
        } catch (e) {
          debugPrint('Express audio upload: $e');
        }
        
        if (audioUrl != null) {
          _sosLog.insert(0, '✅ SOS Audio evidence sent to Admin Dashboard');
        } else {
          _sosLog.insert(0, '✅ Audio stored and relayed to Safety Gateway');
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Audio upload error: $e');
      _sosLog.insert(0, '❌ Audio upload error: ${e.toString().split('\n').first}');
      notifyListeners();
    }
  }

  // Trip Monitoring
  final dio.Dio _dio = dio.Dio(dio.BaseOptions(
    connectTimeout: const Duration(seconds: 180),
    receiveTimeout: const Duration(seconds: 180),
  ));
  
  static String get _backendUrl => ApiConfig.baseUrl;


  Future<String?> startTrip(String destination, {String? origin}) async {
    try {
      final response = await _dio.post(
        '$_backendUrl/api/routes/safest',
        data: {
          'origin': origin != null && origin.isNotEmpty ? origin : '$_currentLat,$_currentLng',
          'destination': destination,
        },
        options: dio.Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.data['success'] == true) {
        final data = response.data['safestRoute'];

        final List<LatLng> path = (data['path'] as List).map((p) =>
          LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())
        ).toList();

        final List<NavigationInstruction> instructions = (data['instructions'] as List).map((i) =>
          NavigationInstruction(
            instruction: i['instruction'] ?? '',
            distance: i['distance'] ?? '',
            icon: _getIconForInstruction(i['instruction'] ?? ''),
            isSafeZone: i['isSafeZone'] ?? true,
          )
        ).toList();

        _currentTrip = TripSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          startTime: DateTime.now(),
          startLat: _currentLat,
          startLng: _currentLng,
          destination: destination,
          instructions: instructions,
          path: path,
          distanceKm: data['distanceKm']?.toString() ?? '',
          durationMin: (data['durationMin'] as num?)?.toInt() ?? 0,
        );
        _isTripActive = true;
        _currentInstructionIndex = 0;
        
        // Initialize stats immediately
        _updateNavStats();
        notifyListeners();

        // Notify contacts if trip sharing is enabled
        if (_tripSharingEnabled && _emergencyContacts.isNotEmpty) {
          final url = 'https://maps.google.com/?q=$_currentLat,$_currentLng';
          final msg = Uri.encodeComponent(
              '🗺️ I started a trip to "$destination". Track me: $url');
          for (final contact in _emergencyContacts) {
            if (contact.phone.isEmpty) continue;
            final smsUri = Uri.parse('sms:${contact.phone}?body=$msg');
            try { await launchUrl(smsUri); } catch (_) {}
          }
          _sosLog.insert(0, '📤 Trip start shared with contacts');
        }

        if (response.data['status'] == 'Risky') {
          simulateAnomaly('Risky Route');
        }

        notifyListeners();
        return null; // success
      }
      
      // Fallback directly to Google Maps if backend returned success=false
      return await _startTripWithGoogleDirect(destination, origin: origin);
    } catch (e) {
      debugPrint('Backend trip route failed ($e). Falling back to Google Maps Routes API directly...');
      return await _startTripWithGoogleDirect(destination, origin: origin);
    }
  }

  Future<String?> _startTripWithGoogleDirect(String destination, {String? origin}) async {
    const googleApiKey = 'AIzaSyBysLlo3koysojda0_SYVBPszM7WxcPs6U';
    try {
      double origLat = _currentLat != 0.0 ? _currentLat : 19.9975;
      double origLng = _currentLng != 0.0 ? _currentLng : 73.7898;
      if (origin != null && origin.contains(',')) {
        final parts = origin.split(',');
        origLat = double.tryParse(parts[0].trim()) ?? origLat;
        origLng = double.tryParse(parts[1].trim()) ?? origLng;
      }

      double? destLat;
      double? destLng;
      if (destination.contains(',')) {
        final parts = destination.split(',');
        destLat = double.tryParse(parts[0].trim());
        destLng = double.tryParse(parts[1].trim());
      }

      // If text place name, search via Google Places API (New)
      if (destLat == null || destLng == null) {
        try {
          final placeRes = await _dio.post(
            'https://places.googleapis.com/v1/places:searchText',
            data: {'textQuery': '$destination, Maharashtra, India'},
            options: dio.Options(
              headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': googleApiKey,
                'X-Goog-FieldMask': 'places.displayName,places.location',
              },
            ),
          );
          if (placeRes.data?['places'] != null && (placeRes.data['places'] as List).isNotEmpty) {
            final loc = placeRes.data['places'][0]['location'];
            destLat = (loc['latitude'] as num).toDouble();
            destLng = (loc['longitude'] as num).toDouble();
          }
        } catch (placeErr) {
          debugPrint('Google Places search error: $placeErr');
        }
      }

      if (destLat == null || destLng == null) {
        return 'Could not locate destination "$destination".';
      }

      final routeRes = await _dio.post(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        data: {
          'origin': {'location': {'latLng': {'latitude': origLat, 'longitude': origLng}}},
          'destination': {'location': {'latLng': {'latitude': destLat, 'longitude': destLng}}},
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
          'computeAlternativeRoutes': false,
        },
        options: dio.Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': googleApiKey,
            'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs.steps',
          },
        ),
      );

      if (routeRes.data?['routes'] != null && (routeRes.data['routes'] as List).isNotEmpty) {
        final r = routeRes.data['routes'][0];
        final enc = r['polyline']?['encodedPolyline'] ?? '';
        final List<LatLng> path = _decodePolyline(enc);
        final int distMeters = (r['distanceMeters'] as num?)?.toInt() ?? 0;
        final String distKm = (distMeters / 1000).toStringAsFixed(1);
        final String durStr = r['duration']?.toString().replaceAll('s', '') ?? '0';
        final int durMin = (int.tryParse(durStr) ?? 0) ~/ 60;

        final List<NavigationInstruction> instructions = [];
        final steps = r['legs']?[0]?['steps'] as List? ?? [];
        for (final st in steps) {
          final String text = st['navigationInstruction']?['instructions'] ?? 'Follow road';
          final int stepDist = (st['distanceMeters'] as num?)?.toInt() ?? 0;
          instructions.add(NavigationInstruction(
            instruction: text,
            distance: stepDist < 1000 ? '${stepDist}m' : '${(stepDist / 1000).toStringAsFixed(1)}km',
            icon: _getIconForInstruction(text),
            isSafeZone: true,
          ));
        }

        if (instructions.isEmpty) {
          instructions.add(NavigationInstruction(
            instruction: 'Drive towards destination',
            distance: '${distKm}km',
            icon: Icons.navigation_rounded,
            isSafeZone: true,
          ));
        }

        _currentTrip = TripSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          startTime: DateTime.now(),
          startLat: origLat,
          startLng: origLng,
          destination: destination,
          instructions: instructions,
          path: path.isNotEmpty ? path : [LatLng(origLat, origLng), LatLng(destLat, destLng)],
          distanceKm: distKm,
          durationMin: durMin > 0 ? durMin : 1,
        );
        _isTripActive = true;
        _currentInstructionIndex = 0;
        _updateNavStats();
        notifyListeners();
        return null;
      }
      return 'Google Routes could not find a path to "$destination"';
    } catch (e) {
      debugPrint('Google direct routing error: $e');
      return 'Routing error: ${e.toString().split('\n').first}';
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  IconData _getIconForInstruction(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('turn right')) return Icons.turn_right_rounded;
    if (lower.contains('turn left')) return Icons.turn_left_rounded;
    if (lower.contains('arrive')) return Icons.location_on_rounded;
    if (lower.contains('straight')) return Icons.straight_rounded;
    if (lower.contains('caution')) return Icons.warning_amber_rounded;
    return Icons.navigation_rounded;
  }




  void endTrip() {
    if (_currentTrip != null) {
      _currentTrip!.endTime = DateTime.now();
      _currentTrip!.isActive = false;
    }
    _isTripActive = false;
    _currentInstructionIndex = 0;
    _dangerZoneAlert = false;
    notifyListeners();
  }

  // Fake Call
  void triggerFakeCall() {
    _isFakeCallActive = true;
    notifyListeners();
  }

  void endFakeCall() {
    _isFakeCallActive = false;
    notifyListeners();
  }

  // AI Companion
  void toggleAICompanion() {
    _isAICompanionActive = !_isAICompanionActive;
    notifyListeners();
  }

  // Community Reports
  void addReport(SafetyReport report) async {
    // Optimistic UI update
    if (!_communityReports.any((r) => r.id == report.id)) {
      _communityReports.insert(0, report);
      notifyListeners();
    }
    
    // Sync to Supabase
    await SupabaseService.logIncident(
      title: report.type.toUpperCase(), // Using type as title for default
      type: report.type,
      severity: 'Medium',
      lat: report.lat,
      lng: report.lng,
      address: 'Reported Location',
      description: report.description,
      riskScore: 50,
      source: _userName ?? 'Mobile App',
    );
    
    // Refresh to get any server-side data
    fetchCommunityReports();
  }

  void upvoteReport(String reportId) {
    // In a real app, this would update the report's upvotes
    notifyListeners();
  }

  // Emergency Contacts
  Future<void> addEmergencyContact(EmergencyContact contact) async {
    _emergencyContacts.add(contact);
    notifyListeners();

    if (_userEmail != null) {
      await SupabaseService.syncContact(
        userEmail: _userEmail!,
        name: contact.name,
        phone: contact.phone,
        relation: contact.relationship,
      );
      // Re-fetch to get the real DB IDs and ensure consistency
      await fetchContacts();
    }
  }

  void removeEmergencyContact(String id) {
    _emergencyContacts.removeWhere((c) => c.id == id);
    notifyListeners();
    SupabaseService.deleteContact(id);
  }

  // ── Location Sharing Controls ──────────────────────────────────────────────

  /// Toggle 1: Continuous Tracking — periodically sends a Google Maps link via SMS
  void toggleContinuousTracking(bool enabled) {
    _continuousTrackingEnabled = enabled;
    if (enabled) {
      _startContinuousSharing();
      _sosLog.insert(0, '📡 Continuous tracking started');
    } else {
      _continuousShareTimer?.cancel();
      _sosLog.insert(0, '🔕 Continuous tracking stopped');
    }
    notifyListeners();
  }

  void _startContinuousSharing() {
    _continuousShareTimer?.cancel();
    // Send immediately, then every 10 minutes
    _shareLocationLinkWithPrimary(label: '📍 Live Location Update');
    _continuousShareTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (_continuousTrackingEnabled) {
        _shareLocationLinkWithPrimary(label: '📍 Live Location Update');
      }
    });
  }

  /// Toggle 2: SOS Auto-Share — controls whether location is sent to ALL contacts on SOS
  void toggleSOSAutoShare(bool enabled) {
    _sosAutoShareEnabled = enabled;
    _sosLog.insert(
        0, enabled ? '🚨 SOS auto-share enabled' : '🔕 SOS auto-share disabled');
    notifyListeners();
  }

  /// Toggle 3: Trip Sharing — controls whether contacts get a link when a trip starts
  void toggleTripSharing(bool enabled) {
    _tripSharingEnabled = enabled;
    _sosLog.insert(
        0, enabled ? '🗺️ Trip sharing enabled' : '🔕 Trip sharing disabled');
    notifyListeners();
  }

  /// Sends an SMS/WhatsApp location link to all emergency contacts.
  Future<void> sendLocationLinkToAll({String label = '📍 My current location'}) async {
    final url = 'https://maps.google.com/?q=$_currentLat,$_currentLng';
    final message = Uri.encodeComponent('$label $url');
    for (final contact in _emergencyContacts) {
      if (contact.phone.isEmpty) continue;
      final smsUri = Uri.parse('sms:${contact.phone}?body=$message');
      try {
        await launchUrl(smsUri);
      } catch (_) {}
    }
    _sosLog.insert(0, '✅ Location link sent to all contacts');
    notifyListeners();
  }

  /// Sends a location link to the primary trusted contact only.
  Future<void> _shareLocationLinkWithPrimary({required String label}) async {
    final primary = _emergencyContacts.isNotEmpty ? _emergencyContacts.first : null;
    if (primary == null) return;
    final url = 'https://maps.google.com/?q=$_currentLat,$_currentLng';
    final message = Uri.encodeComponent('$label ${primary.name}! $url');
    final smsUri = Uri.parse('sms:${primary.phone}?body=$message');
    try {
      await launchUrl(smsUri);
    } catch (e) {
      debugPrint('[LocationShare] SMS launch error: $e');
    }
  }

  // Anomaly Detection
  void simulateAnomaly(String type) {
    _anomalyDetected = true;
    _anomalyType = type;
    notifyListeners();
    
    // Auto-clear after 10 seconds if not handled
    Future.delayed(const Duration(seconds: 10), () {
      if (_anomalyDetected) {
        _anomalyDetected = false;
        _anomalyType = '';
        notifyListeners();
      }
    });
  }

  void dismissAnomaly() {
    _anomalyDetected = false;
    _anomalyType = '';
    notifyListeners();
  }

  // Update location manually
  void updateLocation(double lat, double lng) {
    if (_currentLat == lat && _currentLng == lng) return;
    _currentLat = lat;
    _currentLng = lng;
    
    _updateRiskAssessment();
    _checkPathDivergence();
    
    // Removed redundant weather fetch call that caused race condition
    
    // Push live tracking update if SOS is active
    if (_isSOSActive && _currentSOSId != null) {
      SupabaseService.updateSOSLocation(
        logId: _currentSOSId!,
        latitude: lat,
        longitude: lng,
      );
    }

    // Generic periodic location sync for Admin "Click-to-Track"
    if (_userEmail != null) {
      final now = DateTime.now();
      if (_lastDbLocationUpdate == null || now.difference(_lastDbLocationUpdate!).inSeconds > 60) {
        _lastDbLocationUpdate = now;
        SupabaseService.updateUserLocation(
          email: _userEmail!,
          lat: lat,
          lng: lng,
        );
      }
    }

    // Fetch safe places if not done or location changed significantly
    if (!_fetchedDynamicPlaces) {
       _fetchLiveSafePlaces(lat, lng);
    }
    
    notifyListeners();
  }

  /// Fetches real-world safe places (Police Stations & Hospitals) around given coords
  /// using the OpenStreetMap Overpass API.
  Future<void> _fetchLiveSafePlaces(double lat, double lng) async {
    // Flag so we don't spam the API on every single GPS tick
    _fetchedDynamicPlaces = true;
    
    try {
      final dioClient = dio.Dio(dio.BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));

      // Overpass QL to find police and hospitals within 5km radius
      final query = """
      [out:json][timeout:25];
      (
        node["amenity"="police"](around:5000, $lat, $lng);
        way["amenity"="police"](around:5000, $lat, $lng);
        node["amenity"="hospital"](around:5000, $lat, $lng);
        way["amenity"="hospital"](around:5000, $lat, $lng);
      );
      out body;
      >;
      out skel qt;
      """;

      final response = await dioClient.get(
        'https://overpass-api.de/api/interpreter',
        queryParameters: {'data': query},
      );

      if (response.data != null && response.data['elements'] != null) {
        final List elements = response.data['elements'] as List;
        final List<SafePlace> dynamicPlaces = [];

        for (var element in elements) {
          if (element['type'] == 'node') {
            final double pLat = (element['lat'] as num).toDouble();
            final double pLng = (element['lon'] as num).toDouble();
            final Map? tags = element['tags'];
            if (tags == null) continue;

            final String name = tags['name'] ?? tags['operator'] ?? 'Public Service';
            final String amenity = tags['amenity'] ?? '';
            
            SafePlaceType type = SafePlaceType.safeZone;
            if (amenity == 'police') type = SafePlaceType.policeStation;
            if (amenity == 'hospital') type = SafePlaceType.hospital;

            dynamicPlaces.add(SafePlace(
              lat: pLat,
              lng: pLng,
              name: name,
              type: type,
              rating: 4.0 + (math.Random().nextDouble() * 1.0),
            ));
          }
        }

        if (dynamicPlaces.isNotEmpty) {
          _safePlaces.clear();
          // Add Nagpur/Nashik static defaults back in
          _safePlaces.addAll(SafetyModels.getSafePlaces());
          // Add the real-world live ones found
          _safePlaces.addAll(dynamicPlaces);
          debugPrint('[SafetyService] Loaded ${dynamicPlaces.length} live safe places from OpenStreetMap');
          
          // Persist discovered safe places to local disk for offline access
          _offlineMapService?.saveZonesLocally(
            safePlaces: _safePlaces,
            hotspots: SafetyModels.getCrimeHotspots(),
            centerLat: lat,
            centerLng: lng,
            areaName: 'Local Zone (${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)})',
          );
          
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[SafetyService] Error fetching dynamic safe places: $e');
      // Keep static defaults on failure
    }
  }

  Future<void> fetchLiveLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      updateLocation(pos.latitude, pos.longitude);
      // Ensure weather is also updated immediately
      if (_weatherService != null) {
        _weatherService!.fetchWeather(pos.latitude, pos.longitude);
      }
    } catch (e) {
      debugPrint('Live location update error: $e');
    }
  }

  /// Searches for a place by name within the predefined SafePlaces.
  /// Returns the SafePlace if found, or null otherwise.
  SafePlace? searchPlace(String query) {
    if (query.isEmpty) return null;
    
    final normalizedQuery = query.toLowerCase().trim();
    final safePlaces = SafetyModels.getSafePlaces();
    
    try {
      return safePlaces.firstWhere(
        (place) => place.name.toLowerCase().contains(normalizedQuery) || 
                   place.typeLabel.toLowerCase().contains(normalizedQuery)
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _riskTimer?.cancel();
    _anomalyTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }
}
