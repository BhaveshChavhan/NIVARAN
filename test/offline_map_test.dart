import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:nivaran/models/safety_models.dart';

void main() {
  group('Offline Map & Zone Serialization Tests', () {
    test('CrimeHotspot serialization and deserialization preserves all fields', () {
      final hotspot = CrimeHotspot(
        lat: 19.9975,
        lng: 73.7898,
        intensity: 0.85,
        type: 'Assault Zone',
        area: 'College Road',
        boundary: [
          const LatLng(19.990, 73.780),
          const LatLng(20.000, 73.780),
          const LatLng(20.000, 73.790),
          const LatLng(19.990, 73.790),
        ],
      );

      final json = hotspot.toJson();
      final restored = CrimeHotspot.fromJson(json);

      expect(restored.lat, equals(19.9975));
      expect(restored.lng, equals(73.7898));
      expect(restored.intensity, equals(0.85));
      expect(restored.type, equals('Assault Zone'));
      expect(restored.area, equals('College Road'));
      expect(restored.boundary, isNotNull);
      expect(restored.boundary!.length, equals(4));
      expect(restored.boundary![0].latitude, equals(19.990));
      expect(restored.boundary![0].longitude, equals(73.780));
    });

    test('SafePlace serialization and deserialization preserves categories', () {
      final policeStation = SafePlace(
        lat: 19.9950,
        lng: 73.7860,
        name: 'Sarkarwada PS',
        type: SafePlaceType.policeStation,
        rating: 4.8,
      );

      final hospital = SafePlace(
        lat: 21.1350,
        lng: 79.0950,
        name: 'GMCH Hospital',
        type: SafePlaceType.hospital,
        rating: 4.6,
      );

      final jsonPolice = policeStation.toJson();
      final jsonHospital = hospital.toJson();

      final restoredPolice = SafePlace.fromJson(jsonPolice);
      final restoredHospital = SafePlace.fromJson(jsonHospital);

      expect(restoredPolice.type, equals(SafePlaceType.policeStation));
      expect(restoredPolice.typeEmoji, equals('🚔'));
      expect(restoredHospital.type, equals(SafePlaceType.hospital));
      expect(restoredHospital.typeEmoji, equals('🏥'));
    });

    test('OfflineZoneBundle packages multiple hotspots and safe places', () {
      final bundle = OfflineZoneBundle(
        areaName: 'Nashik Metropolitan Zone',
        centerLat: 19.9975,
        centerLng: 73.7898,
        radiusKm: 5.0,
        cachedAt: DateTime(2026, 10, 7, 12, 0, 0),
        hotspots: [
          CrimeHotspot(
            lat: 19.9950,
            lng: 73.7860,
            intensity: 0.9,
            type: 'Theft',
            area: 'CBS',
          ),
        ],
        safePlaces: [
          SafePlace(
            lat: 19.9900,
            lng: 73.8000,
            name: 'Six Sigma Hospital',
            type: SafePlaceType.hospital,
            rating: 4.5,
          ),
        ],
      );

      final json = bundle.toJson();
      final restored = OfflineZoneBundle.fromJson(json);

      expect(restored.areaName, equals('Nashik Metropolitan Zone'));
      expect(restored.hotspots.length, equals(1));
      expect(restored.safePlaces.length, equals(1));
      expect(restored.hotspots.first.area, equals('CBS'));
      expect(restored.safePlaces.first.name, equals('Six Sigma Hospital'));
    });
  });
}
