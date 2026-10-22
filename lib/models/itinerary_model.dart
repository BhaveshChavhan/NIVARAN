import 'package:flutter/material.dart';

class ItineraryStop {
  final String id;
  final String name;
  final String category;
  final String timeSlot;
  final double lat;
  final double lng;
  final double safetyRating;
  final String policeStationNearby;
  final String safeVisitingHours;
  final String safetyTip;
  bool isCompleted;

  ItineraryStop({
    required this.id,
    required this.name,
    required this.category,
    required this.timeSlot,
    required this.lat,
    required this.lng,
    required this.safetyRating,
    required this.policeStationNearby,
    required this.safeVisitingHours,
    required this.safetyTip,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'timeSlot': timeSlot,
    'lat': lat,
    'lng': lng,
    'safetyRating': safetyRating,
    'policeStationNearby': policeStationNearby,
    'safeVisitingHours': safeVisitingHours,
    'safetyTip': safetyTip,
    'isCompleted': isCompleted,
  };

  factory ItineraryStop.fromJson(Map<String, dynamic> json) => ItineraryStop(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    category: json['category'] ?? 'Sightseeing',
    timeSlot: json['timeSlot'] ?? '',
    lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    safetyRating: (json['safetyRating'] as num?)?.toDouble() ?? 4.5,
    policeStationNearby: json['policeStationNearby'] ?? 'Local PS within 1km',
    safeVisitingHours: json['safeVisitingHours'] ?? 'Daylight hours recommended',
    safetyTip: json['safetyTip'] ?? 'Stay on verified pedestrian corridors.',
    isCompleted: json['isCompleted'] ?? false,
  );

  IconData get categoryIcon {
    switch (category.toLowerCase()) {
      case 'heritage':
      case 'monument':
        return Icons.castle_rounded;
      case 'temple':
        return Icons.temple_hindu_rounded;
      case 'market':
      case 'shopping':
        return Icons.storefront_rounded;
      case 'scenic':
      case 'nature':
        return Icons.landscape_rounded;
      case 'dining':
      case 'food':
        return Icons.restaurant_rounded;
      case 'museum':
        return Icons.museum_rounded;
      case 'transit hub':
      case 'station':
        return Icons.train_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Color get categoryColor {
    switch (category.toLowerCase()) {
      case 'heritage':
        return const Color(0xFFD97706);
      case 'temple':
        return const Color(0xFFEA580C);
      case 'market':
        return const Color(0xFF2563EB);
      case 'scenic':
        return const Color(0xFF059669);
      case 'dining':
        return const Color(0xFFE11D48);
      case 'museum':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF0284C7);
    }
  }
}

class SafeItinerary {
  final String id;
  final String title;
  final String city;
  final String description;
  final String tripDate;
  final String startTime;
  final String endTime;
  final int safetyScore; // 0 - 100
  final String riskLevel; // 'Very Safe', 'Safe', 'Moderate'
  final List<ItineraryStop> stops;
  final int checkInIntervalMinutes;
  final bool isSharedWithContacts;
  final bool nightWarning;
  final DateTime createdAt;

  SafeItinerary({
    required this.id,
    required this.title,
    required this.city,
    required this.description,
    required this.tripDate,
    required this.startTime,
    required this.endTime,
    required this.safetyScore,
    required this.riskLevel,
    required this.stops,
    this.checkInIntervalMinutes = 60,
    this.isSharedWithContacts = true,
    this.nightWarning = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'city': city,
    'description': description,
    'tripDate': tripDate,
    'startTime': startTime,
    'endTime': endTime,
    'safetyScore': safetyScore,
    'riskLevel': riskLevel,
    'stops': stops.map((s) => s.toJson()).toList(),
    'checkInIntervalMinutes': checkInIntervalMinutes,
    'isSharedWithContacts': isSharedWithContacts,
    'nightWarning': nightWarning,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SafeItinerary.fromJson(Map<String, dynamic> json) => SafeItinerary(
    id: json['id'] ?? '',
    title: json['title'] ?? 'Safe Tourist Itinerary',
    city: json['city'] ?? 'Nashik',
    description: json['description'] ?? '',
    tripDate: json['tripDate'] ?? 'Today',
    startTime: json['startTime'] ?? '09:00 AM',
    endTime: json['endTime'] ?? '06:00 PM',
    safetyScore: json['safetyScore'] ?? 92,
    riskLevel: json['riskLevel'] ?? 'Safe',
    stops: (json['stops'] as List<dynamic>?)
            ?.map((item) => ItineraryStop.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [],
    checkInIntervalMinutes: json['checkInIntervalMinutes'] ?? 60,
    isSharedWithContacts: json['isSharedWithContacts'] ?? true,
    nightWarning: json['nightWarning'] ?? false,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
        : DateTime.now(),
  );

  static List<SafeItinerary> getCuratedTouristItineraries() {
    return [
      SafeItinerary(
        id: 'curated-nashik-heritage',
        title: 'Nashik Heritage & Temple Safe Trail',
        city: 'Nashik',
        description: 'Verified safe cultural circuit with dedicated tourist police coverage and pedestrian paths.',
        tripDate: 'Day Trip (Recommended)',
        startTime: '08:30 AM',
        endTime: '05:30 PM',
        safetyScore: 96,
        riskLevel: 'Very Safe',
        checkInIntervalMinutes: 60,
        isSharedWithContacts: true,
        nightWarning: false,
        stops: [
          ItineraryStop(
            id: 'stop-1',
            name: 'Panchavati & Kalaram Temple',
            category: 'Temple',
            timeSlot: '09:00 AM - 11:00 AM',
            lat: 20.0050,
            lng: 73.7920,
            safetyRating: 4.8,
            policeStationNearby: 'Panchavati Police Station (350m)',
            safeVisitingHours: '06:00 AM - 07:00 PM',
            safetyTip: 'Official temple trust entrance; beware of unverified private guides.',
          ),
          ItineraryStop(
            id: 'stop-2',
            name: 'Sarkarwada & Old Heritage Museum',
            category: 'Heritage',
            timeSlot: '11:30 AM - 01:00 PM',
            lat: 19.9975,
            lng: 73.7898,
            safetyRating: 4.9,
            policeStationNearby: 'Sarkarwada PS (Adjacent 50m)',
            safeVisitingHours: '10:00 AM - 05:00 PM',
            safetyTip: 'Government museum with CCTV surveillance and security staff.',
          ),
          ItineraryStop(
            id: 'stop-3',
            name: 'College Road Tourist Safe Zone & Lunch',
            category: 'Dining',
            timeSlot: '01:30 PM - 03:00 PM',
            lat: 19.9990,
            lng: 73.7700,
            safetyRating: 4.7,
            policeStationNearby: 'Gangapur PS (800m)',
            safeVisitingHours: '10:00 AM - 10:00 PM',
            safetyTip: 'Well-lit commercial zone with verified prepaid autos & cabs.',
          ),
          ItineraryStop(
            id: 'stop-4',
            name: 'Pandavleni Caves & Buddha Vihar',
            category: 'Scenic',
            timeSlot: '03:30 PM - 05:30 PM',
            lat: 19.9570,
            lng: 73.7480,
            safetyRating: 4.6,
            policeStationNearby: 'Ambad PS (1.2km)',
            safeVisitingHours: '08:00 AM - 05:30 PM',
            safetyTip: 'Descend before sunset; stay on the designated stone stairway.',
          ),
        ],
      ),
      SafeItinerary(
        id: 'curated-nagpur-culture',
        title: 'Nagpur Monuments & Green Corridor',
        city: 'Nagpur',
        description: 'Explore the Zero Mile Marker, Deekshabhoomi, and Futala Lake within safe tourist corridors.',
        tripDate: 'Day Trip (Recommended)',
        startTime: '09:00 AM',
        endTime: '06:00 PM',
        safetyScore: 94,
        riskLevel: 'Very Safe',
        checkInIntervalMinutes: 60,
        isSharedWithContacts: true,
        nightWarning: false,
        stops: [
          ItineraryStop(
            id: 'ngp-1',
            name: 'Zero Mile Stone & Heritage Precinct',
            category: 'Heritage',
            timeSlot: '09:30 AM - 10:45 AM',
            lat: 21.1470,
            lng: 79.0830,
            safetyRating: 4.8,
            policeStationNearby: 'Sitabuldi PS (400m)',
            safeVisitingHours: '08:00 AM - 07:00 PM',
            safetyTip: 'Metro connected; use Zero Mile Metro Station for secure commute.',
          ),
          ItineraryStop(
            id: 'ngp-2',
            name: 'Deekshabhoomi World Stupa',
            category: 'Monument',
            timeSlot: '11:15 AM - 01:15 PM',
            lat: 21.1278,
            lng: 79.0664,
            safetyRating: 4.9,
            policeStationNearby: 'Bajaj Nagar PS (600m)',
            safeVisitingHours: '06:00 AM - 08:00 PM',
            safetyTip: 'High-security zone with regular police patrols and visitor assistance.',
          ),
          ItineraryStop(
            id: 'ngp-3',
            name: 'Dharampeth Cultural & Handicraft Market',
            category: 'Market',
            timeSlot: '02:00 PM - 03:45 PM',
            lat: 21.1390,
            lng: 79.0620,
            safetyRating: 4.7,
            policeStationNearby: 'Ambazari PS (750m)',
            safeVisitingHours: '11:00 AM - 09:00 PM',
            safetyTip: 'Registered artisan shops; UPI and card payments widely accepted.',
          ),
          ItineraryStop(
            id: 'ngp-4',
            name: 'Futala Lake Illuminated Waterfront Promenade',
            category: 'Scenic',
            timeSlot: '04:15 PM - 06:00 PM',
            lat: 21.1530,
            lng: 79.0470,
            safetyRating: 4.6,
            policeStationNearby: 'Gittikhadan PS (900m)',
            safeVisitingHours: '07:00 AM - 07:30 PM',
            safetyTip: 'Stick to the illuminated main promenade; avoid unlit side paths.',
          ),
        ],
      ),
      SafeItinerary(
        id: 'curated-golden-heritage',
        title: 'Golden Heritage Safe Tourist Trail',
        city: 'Jaipur',
        description: 'Pink City royal palaces, observatory, and handicraft bazaar with tourist escort assistance.',
        tripDate: 'Day Trip (Recommended)',
        startTime: '08:30 AM',
        endTime: '05:30 PM',
        safetyScore: 95,
        riskLevel: 'Very Safe',
        checkInIntervalMinutes: 45,
        isSharedWithContacts: true,
        nightWarning: false,
        stops: [
          ItineraryStop(
            id: 'jpr-1',
            name: 'Hawa Mahal & Tourist Assistance Booth',
            category: 'Heritage',
            timeSlot: '09:00 AM - 10:30 AM',
            lat: 26.9239,
            lng: 75.8267,
            safetyRating: 4.9,
            policeStationNearby: 'Manak Chowk PS (250m)',
            safeVisitingHours: '09:00 AM - 05:00 PM',
            safetyTip: 'Registered Rajasthan Tourist Police booth located right opposite entrance.',
          ),
          ItineraryStop(
            id: 'jpr-2',
            name: 'City Palace & UNESCO Jantar Mantar',
            category: 'Heritage',
            timeSlot: '11:00 AM - 01:30 PM',
            lat: 26.9258,
            lng: 75.8237,
            safetyRating: 4.9,
            policeStationNearby: 'Tourist Police Control Room (200m)',
            safeVisitingHours: '09:30 AM - 05:00 PM',
            safetyTip: 'Composite government entrance tickets available; audio guides available.',
          ),
          ItineraryStop(
            id: 'jpr-3',
            name: 'Bapu Bazaar Verified Artisan Market',
            category: 'Market',
            timeSlot: '02:30 PM - 04:30 PM',
            lat: 26.9180,
            lng: 75.8210,
            safetyRating: 4.7,
            policeStationNearby: 'Kotwali PS (400m)',
            safeVisitingHours: '11:00 AM - 07:00 PM',
            safetyTip: 'Government recognized RTDC craft outlets available on the main road.',
          ),
        ],
      ),
    ];
  }
}

class TouristPlace {
  final String name;
  final String city;
  final String category;
  final double lat;
  final double lng;
  final double safetyRating;
  final String policeStationNearby;
  final String safeVisitingHours;
  final String safetyTip;

  const TouristPlace({
    required this.name,
    required this.city,
    required this.category,
    required this.lat,
    required this.lng,
    required this.safetyRating,
    required this.policeStationNearby,
    required this.safeVisitingHours,
    required this.safetyTip,
  });

  static const List<TouristPlace> allPlaces = [
    // ── Jaipur ──
    TouristPlace(
      name: 'Hawa Mahal (Palace of Winds)',
      city: 'Jaipur',
      category: 'Heritage',
      lat: 26.9239,
      lng: 75.8267,
      safetyRating: 4.9,
      policeStationNearby: 'Manak Chowk PS (250m)',
      safeVisitingHours: '09:00 AM - 05:00 PM',
      safetyTip: 'Tourist Police booth located opposite entrance; CCTV monitored.',
    ),
    TouristPlace(
      name: 'Amber Palace & Jaigarh Fort',
      city: 'Jaipur',
      category: 'Heritage',
      lat: 26.9855,
      lng: 75.8513,
      safetyRating: 4.8,
      policeStationNearby: 'Amer Police Station (300m)',
      safeVisitingHours: '08:00 AM - 05:30 PM',
      safetyTip: 'Use authorized government guides; government ticket counters available.',
    ),
    TouristPlace(
      name: 'City Palace & Museum',
      city: 'Jaipur',
      category: 'Heritage',
      lat: 26.9258,
      lng: 75.8237,
      safetyRating: 4.9,
      policeStationNearby: 'Tourist Police Control Room (200m)',
      safeVisitingHours: '09:30 AM - 05:00 PM',
      safetyTip: 'Safe central tourist corridor; bag security checks at all gates.',
    ),
    TouristPlace(
      name: 'Jantar Mantar Astronomical Observatory',
      city: 'Jaipur',
      category: 'Heritage',
      lat: 26.9248,
      lng: 75.8246,
      safetyRating: 4.8,
      policeStationNearby: 'Kotwali PS (350m)',
      safeVisitingHours: '09:00 AM - 05:00 PM',
      safetyTip: 'UNESCO site with dedicated tourist security personnel.',
    ),
    TouristPlace(
      name: 'Johari & Bapu Bazaar Artisan Walk',
      city: 'Jaipur',
      category: 'Market',
      lat: 26.9180,
      lng: 75.8210,
      safetyRating: 4.7,
      policeStationNearby: 'Manak Chowk PS (200m)',
      safeVisitingHours: '11:00 AM - 07:30 PM',
      safetyTip: 'Government RTDC craft outlets available; avoid unlit interior gallis.',
    ),
    TouristPlace(
      name: 'Nahargarh Fort & Sunset Viewpoint',
      city: 'Jaipur',
      category: 'Scenic',
      lat: 26.9378,
      lng: 75.8156,
      safetyRating: 4.6,
      policeStationNearby: 'Nahargarh Outpost (500m)',
      safeVisitingHours: '10:00 AM - 06:00 PM',
      safetyTip: 'Descend before dark; use verified app cabs or tourist taxis.',
    ),
    TouristPlace(
      name: 'Albert Hall State Museum',
      city: 'Jaipur',
      category: 'Museum',
      lat: 26.9116,
      lng: 75.8195,
      safetyRating: 4.8,
      policeStationNearby: 'Ramganj PS (450m)',
      safeVisitingHours: '09:00 AM - 05:00 PM',
      safetyTip: 'Well illuminated Ram Niwas Bagh gardens; regular police patrols.',
    ),
    TouristPlace(
      name: 'Jal Mahal (Water Palace Promenade)',
      city: 'Jaipur',
      category: 'Scenic',
      lat: 26.9535,
      lng: 75.8462,
      safetyRating: 4.7,
      policeStationNearby: 'Amber PS (600m)',
      safeVisitingHours: '06:00 AM - 07:00 PM',
      safetyTip: 'Well-patrolled lake promenade; brightly lit pedestrian walk.',
    ),
    TouristPlace(
      name: 'Birla Mandir & Moti Dungri',
      city: 'Jaipur',
      category: 'Temple',
      lat: 26.8924,
      lng: 75.8155,
      safetyRating: 4.9,
      policeStationNearby: 'Gandhi Nagar PS (400m)',
      safeVisitingHours: '08:00 AM - 12:00 PM, 04:00 PM - 08:00 PM',
      safetyTip: 'Tranquil white marble complex; safe parking and security checks.',
    ),

    // ── Nashik ──
    TouristPlace(
      name: 'Panchavati & Kalaram Temple',
      city: 'Nashik',
      category: 'Temple',
      lat: 20.0050,
      lng: 73.7920,
      safetyRating: 4.8,
      policeStationNearby: 'Panchavati PS (350m)',
      safeVisitingHours: '06:00 AM - 08:00 PM',
      safetyTip: 'Dedicated temple police outpost; keep belongings in secure locker.',
    ),
    TouristPlace(
      name: 'Ramkund & Godavari Ghats',
      city: 'Nashik',
      category: 'Temple',
      lat: 20.0075,
      lng: 73.7940,
      safetyRating: 4.7,
      policeStationNearby: 'Panchavati PS (400m)',
      safeVisitingHours: '06:00 AM - 07:30 PM',
      safetyTip: 'Stay on wide stone ghats; lifebuoy stations and safety guards present.',
    ),
    TouristPlace(
      name: 'Trimbakeshwar Shiva Jyotirlinga',
      city: 'Nashik',
      category: 'Temple',
      lat: 19.9320,
      lng: 73.5308,
      safetyRating: 4.9,
      policeStationNearby: 'Trimbak PS (300m)',
      safeVisitingHours: '05:30 AM - 08:30 PM',
      safetyTip: 'Queue security verification; verified trust counter for assistance.',
    ),
    TouristPlace(
      name: 'Sula Vineyards & Tasting Lounge',
      city: 'Nashik',
      category: 'Dining',
      lat: 20.0063,
      lng: 73.6882,
      safetyRating: 4.9,
      policeStationNearby: 'Gangapur PS (900m)',
      safeVisitingHours: '11:00 AM - 09:30 PM',
      safetyTip: 'Private gated tourist estate with professional security and valet.',
    ),
    TouristPlace(
      name: 'Pandavleni Ancient Caves',
      city: 'Nashik',
      category: 'Heritage',
      lat: 19.9602,
      lng: 73.7485,
      safetyRating: 4.6,
      policeStationNearby: 'Indira Nagar PS (600m)',
      safeVisitingHours: '08:00 AM - 05:30 PM',
      safetyTip: 'Ascend paved stone steps during daylight; carry water and footwear.',
    ),
    TouristPlace(
      name: 'Muktidham Marble Temple Complex',
      city: 'Nashik',
      category: 'Temple',
      lat: 19.9575,
      lng: 73.8322,
      safetyRating: 4.8,
      policeStationNearby: 'Nashik Road PS (350m)',
      safeVisitingHours: '06:00 AM - 08:00 PM',
      safetyTip: 'High-security campus located near Nashik Road Station.',
    ),

    // ── Nagpur ──
    TouristPlace(
      name: 'Deekshabhoomi Sacred Monument',
      city: 'Nagpur',
      category: 'Heritage',
      lat: 21.1278,
      lng: 79.0664,
      safetyRating: 4.9,
      policeStationNearby: 'Bajaj Nagar PS (400m)',
      safeVisitingHours: '06:00 AM - 08:00 PM',
      safetyTip: 'Peaceful monument grounds; round-the-clock security and tourist police.',
    ),
    TouristPlace(
      name: 'Futala Lake Promenade & Fountains',
      city: 'Nagpur',
      category: 'Scenic',
      lat: 21.1539,
      lng: 79.0435,
      safetyRating: 4.6,
      policeStationNearby: 'Ambazari PS (450m)',
      safeVisitingHours: '07:00 AM - 08:30 PM',
      safetyTip: 'Stick to the illuminated main promenade; avoid unlit side paths.',
    ),
    TouristPlace(
      name: 'Sitabuldi Fort Heritage Area',
      city: 'Nagpur',
      category: 'Heritage',
      lat: 21.1472,
      lng: 79.0833,
      safetyRating: 4.8,
      policeStationNearby: 'Sitabuldi PS (300m)',
      safeVisitingHours: '09:00 AM - 05:00 PM',
      safetyTip: 'Historical fort area with army/police monitoring; check open dates.',
    ),
    TouristPlace(
      name: 'Zero Mile Stone Heritage Center',
      city: 'Nagpur',
      category: 'Heritage',
      lat: 21.1498,
      lng: 79.0806,
      safetyRating: 4.7,
      policeStationNearby: 'Sitabuldi PS (250m)',
      safeVisitingHours: '08:00 AM - 07:00 PM',
      safetyTip: 'Geographical center of India monument; safe public walking plaza.',
    ),
    TouristPlace(
      name: 'Dragon Palace Buddhist Temple',
      city: 'Nagpur',
      category: 'Temple',
      lat: 21.2224,
      lng: 79.1975,
      safetyRating: 4.8,
      policeStationNearby: 'Kamptee PS (500m)',
      safeVisitingHours: '08:00 AM - 06:30 PM',
      safetyTip: 'Beautiful Japanese architecture temple; peaceful landscaped gardens.',
    ),

    // ── Delhi ──
    TouristPlace(
      name: 'Red Fort (Lal Qila)',
      city: 'Delhi',
      category: 'Heritage',
      lat: 28.6562,
      lng: 77.2410,
      safetyRating: 4.8,
      policeStationNearby: 'Kotwali PS (300m)',
      safeVisitingHours: '09:30 AM - 04:30 PM',
      safetyTip: 'High-security UNESCO monument; CISF & Delhi Police coverage.',
    ),
    TouristPlace(
      name: 'India Gate & Kartavya Path',
      city: 'Delhi',
      category: 'Heritage',
      lat: 28.6129,
      lng: 77.2295,
      safetyRating: 4.9,
      policeStationNearby: 'Tilak Marg PS (400m)',
      safeVisitingHours: '06:00 AM - 09:30 PM',
      safetyTip: 'Well illuminated boulevard with heavy tourist police presence.',
    ),
    TouristPlace(
      name: 'Qutub Minar & Iron Pillar',
      city: 'Delhi',
      category: 'Heritage',
      lat: 28.5244,
      lng: 77.1855,
      safetyRating: 4.8,
      policeStationNearby: 'Mehrauli PS (350m)',
      safeVisitingHours: '07:00 AM - 05:00 PM',
      safetyTip: 'Spacious UNESCO complex; verified electronic ticketing.',
    ),
    TouristPlace(
      name: 'Lotus Temple (Bahai House of Worship)',
      city: 'Delhi',
      category: 'Temple',
      lat: 28.5535,
      lng: 77.2588,
      safetyRating: 4.9,
      policeStationNearby: 'Kalkaji PS (500m)',
      safeVisitingHours: '09:00 AM - 05:30 PM',
      safetyTip: 'Strict silence and security protocols; serene landscaped gardens.',
    ),

    // ── Goa ──
    TouristPlace(
      name: 'Basilica of Bom Jesus',
      city: 'Goa',
      category: 'Heritage',
      lat: 15.5009,
      lng: 73.9116,
      safetyRating: 4.9,
      policeStationNearby: 'Old Goa PS (250m)',
      safeVisitingHours: '09:00 AM - 06:30 PM',
      safetyTip: 'World Heritage site; polite tourist police assistance available.',
    ),
    TouristPlace(
      name: 'Fort Aguada & Lighthouse',
      city: 'Goa',
      category: 'Heritage',
      lat: 15.4920,
      lng: 73.7736,
      safetyRating: 4.7,
      policeStationNearby: 'Candolim PS (400m)',
      safeVisitingHours: '09:30 AM - 05:30 PM',
      safetyTip: 'Ocean cliff safety rails in place; visit during daylight hours.',
    ),
    TouristPlace(
      name: 'Calangute & Baga Promenade',
      city: 'Goa',
      category: 'Scenic',
      lat: 15.5439,
      lng: 73.7553,
      safetyRating: 4.6,
      policeStationNearby: 'Calangute Tourist PS (300m)',
      safeVisitingHours: '06:00 AM - 09:00 PM',
      safetyTip: 'Follow lifeguard flags; tourist police patrol along main shacks.',
    ),

    // ── Mumbai ──
    TouristPlace(
      name: 'Gateway of India & Colaba Causeway',
      city: 'Mumbai',
      category: 'Heritage',
      lat: 18.9220,
      lng: 72.8347,
      safetyRating: 4.9,
      policeStationNearby: 'Colaba PS (300m)',
      safeVisitingHours: '07:00 AM - 09:30 PM',
      safetyTip: 'Heavy police outpost and CCTV network; verified ferry counters.',
    ),
    TouristPlace(
      name: "Marine Drive (Queen's Necklace)",
      city: 'Mumbai',
      category: 'Scenic',
      lat: 18.9432,
      lng: 72.8230,
      safetyRating: 4.9,
      policeStationNearby: 'Marine Drive PS (250m)',
      safeVisitingHours: '24 Hours (Patrolled)',
      safetyTip: 'One of the safest promenades in India; regular beat marshals.',
    ),
    TouristPlace(
      name: 'Chhatrapati Shivaji Maharaj Terminus (CSMT)',
      city: 'Mumbai',
      category: 'Heritage',
      lat: 18.9400,
      lng: 72.8353,
      safetyRating: 4.8,
      policeStationNearby: 'Azad Maidan PS (200m)',
      safeVisitingHours: '08:00 AM - 07:00 PM',
      safetyTip: 'Heritage gallery tour; safe pedestrian subways with police security.',
    ),
  ];

  static List<TouristPlace> search(String query, {String? city}) {
    final q = query.trim().toLowerCase();
    List<TouristPlace> list = allPlaces;

    if (city != null && city != 'All' && city.isNotEmpty) {
      final cityMatches = allPlaces.where((p) => p.city.toLowerCase() == city.toLowerCase()).toList();
      if (cityMatches.isNotEmpty) {
        list = cityMatches;
      }
    }

    if (q.isEmpty) {
      return list.take(8).toList();
    }

    final filtered = list.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.city.toLowerCase().contains(q) ||
          p.policeStationNearby.toLowerCase().contains(q);
    }).toList();

    if (filtered.isEmpty && city != null && city != 'All') {
      // Search outside current city if not found
      return allPlaces.where((p) => p.name.toLowerCase().contains(q)).take(8).toList();
    }

    return filtered.take(10).toList();
  }
}

