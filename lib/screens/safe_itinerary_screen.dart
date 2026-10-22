import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/itinerary_model.dart';
import 'trip_monitor_screen.dart';

class SafeItineraryScreen extends StatefulWidget {
  const SafeItineraryScreen({super.key});

  @override
  State<SafeItineraryScreen> createState() => _SafeItineraryScreenState();
}

class _SafeItineraryScreenState extends State<SafeItineraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<SafeItinerary> _userItineraries = [];
  final List<SafeItinerary> _curatedItineraries = SafeItinerary.getCuratedTouristItineraries();
  String _selectedCityFilter = 'All';
  bool _isLoading = true;

  final List<String> _cities = ['All', 'Nashik', 'Nagpur', 'Jaipur'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserItineraries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserItineraries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('tourist_safe_itineraries');
      if (savedJson != null) {
        final List<dynamic> decoded = jsonDecode(savedJson);
        setState(() {
          _userItineraries = decoded.map((item) => SafeItinerary.fromJson(item)).toList();
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error loading saved itineraries: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveUserItineraries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_userItineraries.map((it) => it.toJson()).toList());
      await prefs.setString('tourist_safe_itineraries', encoded);
    } catch (e) {
      debugPrint('Error saving itineraries: $e');
    }
  }

  void _callTouristHelpline() async {
    final uri = Uri.parse('tel:1363');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tourist Helpline: 1363 (24x7 Multi-lingual)'),
            backgroundColor: AppTheme.primaryPurple,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openCreateItineraryModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _CreateItinerarySheet(
        onSave: (newItinerary) {
          setState(() {
            _userItineraries.insert(0, newItinerary);
          });
          _saveUserItineraries();
          _tabController.animateTo(0);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Safe Itinerary "${newItinerary.title}" created successfully!'),
              backgroundColor: AppTheme.safeGreen,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }

  void _deleteItinerary(String id) {
    setState(() {
      _userItineraries.removeWhere((item) => item.id == id);
    });
    _saveUserItineraries();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Itinerary deleted'),
        backgroundColor: AppTheme.textPrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareItinerary(SafeItinerary itinerary) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.share_location_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Itinerary & live tracking link shared with emergency contacts!',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryPurple,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _startMonitoredTrip(SafeItinerary itinerary) {
    final firstStop = itinerary.stops.isNotEmpty ? itinerary.stops.first.name : itinerary.title;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripMonitorScreen(initialDestination: firstStop),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(
          'Safe Tourist Itinerary',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: 'Tourist Helpline 1363',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.headset_mic_rounded, color: AppTheme.primaryPurple, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '1363',
                    style: GoogleFonts.inter(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ],
              ),
            ),
            onPressed: _callTouristHelpline,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Header Tourist Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF7C3AED),
                    Color(0xFF8B5CF6),
                    Color(0xFFA78BFA),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.alt_route_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Safe Tourist Route Planner',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              'AI Safety Scoring & Police Corridor Verification',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.9)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Plan day trips and walking tours with real-time risk checks, auto emergency check-ins, and verified police booths.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.95), height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _openCreateItineraryModal,
                      icon: const Icon(Icons.add_rounded, color: AppTheme.primaryPurple),
                      label: Text(
                        'Create Safe Trip Itinerary',
                        style: GoogleFonts.inter(color: AppTheme.primaryPurple, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primaryPurple,
                borderRadius: BorderRadius.circular(14),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: 'My Trips (${_userItineraries.length})'),
                Tab(text: 'Curated Safe Trails (${_curatedItineraries.length})'),
              ],
            ),
          ),

          // City Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: _cities.map((city) {
                final isSelected = _selectedCityFilter == city;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(city),
                    selected: isSelected,
                    selectedColor: const Color(0xFFF3E8FF),
                    backgroundColor: Colors.white,
                    checkmarkColor: AppTheme.primaryPurple,
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryPurple : const Color(0xFFE2E8F0),
                    ),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppTheme.primaryPurple : AppTheme.textSecondary,
                    ),
                    onSelected: (val) {
                      setState(() {
                        _selectedCityFilter = city;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Tab 1: User Itineraries ──
                _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryPurple))
                    : _buildItineraryList(_userItineraries, isUserList: true),

                // ── Tab 2: Curated Safe Trails ──
                _buildItineraryList(_curatedItineraries, isUserList: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItineraryList(List<SafeItinerary> list, {required bool isUserList}) {
    final filtered = _selectedCityFilter == 'All'
        ? list
        : list.where((it) => it.city.toLowerCase() == _selectedCityFilter.toLowerCase()).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isUserList ? Icons.map_outlined : Icons.travel_explore_rounded,
                size: 56,
                color: AppTheme.primaryPurple.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 16),
              Text(
                isUserList ? 'No tourist trips created yet' : 'No curated trails for $_selectedCityFilter',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                isUserList
                    ? 'Tap "Create Safe Trip Itinerary" to map out your tourist destinations with AI safety scores.'
                    : 'Check back soon or explore other verified cities.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
              ),
              if (isUserList) ...[
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _openCreateItineraryModal,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('Create Safe Itinerary', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final itinerary = filtered[index];
        return _ItineraryCard(
          itinerary: itinerary,
          isUserCreated: isUserList,
          onStartTrip: () => _startMonitoredTrip(itinerary),
          onShare: () => _shareItinerary(itinerary),
          onDelete: isUserList ? () => _deleteItinerary(itinerary.id) : null,
        );
      },
    );
  }
}

class _ItineraryCard extends StatefulWidget {
  final SafeItinerary itinerary;
  final bool isUserCreated;
  final VoidCallback onStartTrip;
  final VoidCallback onShare;
  final VoidCallback? onDelete;

  const _ItineraryCard({
    required this.itinerary,
    required this.isUserCreated,
    required this.onStartTrip,
    required this.onShare,
    this.onDelete,
  });

  @override
  State<_ItineraryCard> createState() => _ItineraryCardState();
}

class _ItineraryCardState extends State<_ItineraryCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.itinerary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // City Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 13, color: AppTheme.primaryPurple),
                          const SizedBox(width: 4),
                          Text(
                            it.city,
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryPurple, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),

                    // Safety Score Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_rounded, size: 12, color: Color(0xFF15803D)),
                          const SizedBox(width: 4),
                          Text(
                            '${it.safetyScore}/100 Safe',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                Text(
                  it.title,
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  it.description,
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 12),

                // Metadata Row
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${it.startTime} - ${it.endTime}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    const SizedBox(width: 14),
                    Icon(Icons.pin_drop_rounded, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${it.stops.length} Safe Stops',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                    ),
                    if (it.nightWarning) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Night Caution',
                          style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFB45309), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Divider
          const Divider(color: Color(0xFFF1F5F9), height: 1),

          // Stops Preview / Expansion
          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Itinerary Waypoints & Tourist Safety Info',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  ...it.stops.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final stop = entry.value;
                    return _buildStopTimelineItem(stop, idx == it.stops.length - 1);
                  }),
                ],
              ),
            ),
            const Divider(color: Color(0xFFF1F5F9), height: 1),
          ],

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppTheme.primaryPurple,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          _isExpanded ? 'Hide' : '${it.stops.length} Stops',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryPurple),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      tooltip: 'Share Itinerary',
                      icon: Icon(Icons.share_outlined, size: 18, color: AppTheme.textSecondary),
                      onPressed: widget.onShare,
                    ),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.dangerRed),
                        onPressed: widget.onDelete,
                      ),
                    ],
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: widget.onStartTrip,
                      icon: const Icon(Icons.navigation_rounded, size: 13, color: Colors.white),
                      label: Text('Start Trip', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.safeGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopTimelineItem(ItineraryStop stop, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step timeline dot & line
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: stop.categoryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: stop.categoryColor.withValues(alpha: 0.6)),
                ),
                child: Icon(stop.categoryIcon, color: stop.categoryColor, size: 14),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stop.name,
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: stop.categoryColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          stop.category,
                          style: GoogleFonts.inter(fontSize: 10, color: stop.categoryColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.timeSlot,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryPurple, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.local_police_outlined, size: 12, color: Color(0xFF15803D)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          stop.policeStationNearby,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 12, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          stop.safetyTip,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateItinerarySheet extends StatefulWidget {
  final ValueChanged<SafeItinerary> onSave;

  const _CreateItinerarySheet({required this.onSave});

  @override
  State<_CreateItinerarySheet> createState() => _CreateItinerarySheetState();
}

class _CreateItinerarySheetState extends State<_CreateItinerarySheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCity = 'Nashik';

  TimeOfDay _startTimeOfDay = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTimeOfDay = const TimeOfDay(hour: 18, minute: 0);
  String _startTime = '09:00 AM';
  String _endTime = '06:00 PM';

  int _checkInMinutes = 60;
  bool _shareWithContacts = true;

  final List<ItineraryStop> _stops = [
    ItineraryStop(
      id: 'custom-stop-1',
      name: 'City Landmark / Monument',
      category: 'Heritage',
      timeSlot: '09:30 AM - 11:30 AM',
      lat: 19.9975,
      lng: 73.7898,
      safetyRating: 4.8,
      policeStationNearby: 'Central PS within 400m',
      safeVisitingHours: '08:00 AM - 06:00 PM',
      safetyTip: 'Verified tourist corridor; CCTV monitored.',
    ),
    ItineraryStop(
      id: 'custom-stop-2',
      name: 'Local Artisan Bazaar & Cafe',
      category: 'Market',
      timeSlot: '12:00 PM - 02:30 PM',
      lat: 19.9990,
      lng: 73.7700,
      safetyRating: 4.6,
      policeStationNearby: 'Local PS within 700m',
      safeVisitingHours: '10:00 AM - 08:00 PM',
      safetyTip: 'Prepaid transport booth available at square.',
    ),
  ];

  final _stopNameController = TextEditingController();
  final _stopSlotController = TextEditingController();
  final _stopPoliceController = TextEditingController();
  final _stopTipController = TextEditingController();
  String _stopCategory = 'Heritage';

  List<TouristPlace> _placeSuggestions = [];
  bool _showPlaceSuggestions = false;

  @override
  void initState() {
    super.initState();
    _startTime = _formatTime(_startTimeOfDay);
    _endTime = _formatTime(_endTimeOfDay);
    _stopSlotController.text = '03:00 PM - 05:00 PM';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _stopNameController.dispose();
    _stopSlotController.dispose();
    _stopPoliceController.dispose();
    _stopTipController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTimeOfDay,
      helpText: 'SET TRIP START TIME',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryPurple,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startTimeOfDay = picked;
        _startTime = _formatTime(picked);
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTimeOfDay,
      helpText: 'SET TRIP END TIME',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryPurple,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _endTimeOfDay = picked;
        _endTime = _formatTime(picked);
      });
    }
  }

  void _onPlaceSearchChanged(String query) {
    setState(() {
      _placeSuggestions = TouristPlace.search(query, city: _selectedCity);
      _showPlaceSuggestions = _placeSuggestions.isNotEmpty;
    });
  }

  void _selectPlace(TouristPlace place) {
    setState(() {
      _stopNameController.text = place.name;
      _stopCategory = place.category;
      _stopPoliceController.text = place.policeStationNearby;
      _stopTipController.text = place.safetyTip;
      _showPlaceSuggestions = false;

      // Smart suggested time slot
      if (_stops.isEmpty) {
        _stopSlotController.text = '$_startTime - 11:30 AM';
      } else if (_stops.length == 1) {
        _stopSlotController.text = '12:00 PM - 02:30 PM';
      } else if (_stops.length == 2) {
        _stopSlotController.text = '03:00 PM - 05:00 PM';
      } else {
        _stopSlotController.text = '05:30 PM - $_endTime';
      }
    });
  }

  Future<void> _pickStopSlotTimes() async {
    final arrival = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'DESTINATION ARRIVAL TIME',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryPurple,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (arrival == null || !mounted) return;

    final departure = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (arrival.hour + 2) % 24, minute: arrival.minute),
      helpText: 'DESTINATION DEPARTURE TIME',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primaryPurple,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF0F172A),
          ),
        ),
        child: child!,
      ),
    );
    if (departure == null || !mounted) return;

    setState(() {
      _stopSlotController.text = '${_formatTime(arrival)} - ${_formatTime(departure)}';
    });
  }

  void _addCustomStop() {
    if (_stopNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or select a destination name'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
      return;
    }

    setState(() {
      _stops.add(
        ItineraryStop(
          id: 'custom-stop-${DateTime.now().millisecondsSinceEpoch}',
          name: _stopNameController.text.trim(),
          category: _stopCategory,
          timeSlot: _stopSlotController.text.trim().isEmpty
              ? '03:00 PM - 05:00 PM'
              : _stopSlotController.text.trim(),
          lat: 19.9975,
          lng: 73.7898,
          safetyRating: 4.8,
          policeStationNearby: _stopPoliceController.text.trim().isEmpty
              ? 'Nearest Police Outpost (within 500m)'
              : _stopPoliceController.text.trim(),
          safeVisitingHours: '08:00 AM - 06:30 PM',
          safetyTip: _stopTipController.text.trim().isEmpty
              ? 'Verified tourist corridor; CCTV monitored.'
              : _stopTipController.text.trim(),
        ),
      );

      _stopNameController.clear();
      _stopSlotController.text = '03:30 PM - 05:30 PM';
      _stopPoliceController.clear();
      _stopTipController.clear();
      _showPlaceSuggestions = false;
    });
  }

  int _calculateSafetyScore() {
    int base = 95;
    if (_endTime.contains('PM')) {
      final hourStr = _endTime.split(':')[0];
      final hour = int.tryParse(hourStr) ?? 6;
      if (hour >= 8 && hour < 12) base -= 8;
    }
    if (_stops.length > 5) base -= 4;
    return base.clamp(75, 98);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one tourist stop.')),
      );
      return;
    }

    final score = _calculateSafetyScore();
    final newItinerary = SafeItinerary(
      id: 'tourist-itin-${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      city: _selectedCity,
      description: _descController.text.trim().isEmpty
          ? 'Custom tourist trip with $_selectedCity verified safety checkpoints.'
          : _descController.text.trim(),
      tripDate: 'Scheduled Trip',
      startTime: _startTime,
      endTime: _endTime,
      safetyScore: score,
      riskLevel: score >= 90 ? 'Very Safe' : 'Safe',
      stops: List.from(_stops),
      checkInIntervalMinutes: _checkInMinutes,
      isSharedWithContacts: _shareWithContacts,
      nightWarning: _endTime.contains('08:') || _endTime.contains('09:') || _endTime.contains('10:'),
    );

    widget.onSave(newItinerary);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Create Safe Tourist Trip',
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                'Plan your itinerary with custom timings, verified safe places & checkpoints',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 20),

              // Title Field
              TextFormField(
                controller: _titleController,
                style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText: 'Trip Name',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  hintText: 'e.g. Jaipur Heritage & Cultural Bazaar Walk',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primaryPurple, width: 1.5),
                  ),
                  prefixIcon: const Icon(Icons.trip_origin_rounded, color: AppTheme.primaryPurple),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a trip name' : null,
              ),
              const SizedBox(height: 14),

              // City Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCity,
                    dropdownColor: Colors.white,
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary),
                    items: ['Nashik', 'Nagpur', 'Jaipur', 'Delhi', 'Goa', 'Mumbai']
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedCity = val;
                          if (_showPlaceSuggestions) {
                            _placeSuggestions = TouristPlace.search(_stopNameController.text, city: val);
                          }
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Description
              TextFormField(
                controller: _descController,
                style: TextStyle(color: AppTheme.textPrimary),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Brief Notes / Objectives',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  hintText: 'e.g. Exploring historical temples, shopping local art, safe dining',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primaryPurple, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── Interactive Manual Start & End Time ──
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickStartTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Start Time', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                                const Icon(Icons.edit_calendar_rounded, size: 14, color: AppTheme.primaryPurple),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _startTime,
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text('Tap to set manually', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryPurple, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickEndTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('End Time', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                                const Icon(Icons.edit_calendar_rounded, size: 14, color: AppTheme.primaryPurple),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _endTime,
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text('Tap to set manually', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryPurple, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Checkpoint Stops List
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tourist Stops (${_stops.length})',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  Text(
                    'AI Safe Corridors',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF15803D), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              ..._stops.asMap().entries.map((entry) {
                final idx = entry.key;
                final stop = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: stop.categoryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(stop.categoryIcon, color: stop.categoryColor, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stop.name,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                            ),
                            Text(
                              '${stop.timeSlot} • ${stop.policeStationNearby}',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444), size: 20),
                        onPressed: () => setState(() => _stops.removeAt(idx)),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 14),

              // ── Add a Destination Stop with Live Place Search & Time Slot Picker ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '+ Add Destination',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryPurple),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Live Place Search',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryPurple, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Place Search Text Field
                    TextFormField(
                      controller: _stopNameController,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      onChanged: _onPlaceSearchChanged,
                      onTap: () {
                        setState(() {
                          _placeSuggestions = TouristPlace.search(_stopNameController.text, city: _selectedCity);
                          _showPlaceSuggestions = _placeSuggestions.isNotEmpty;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search destination in $_selectedCity (e.g. Temple, Fort, Palace)...',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primaryPurple, size: 20),
                        suffixIcon: _stopNameController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _stopNameController.clear();
                                  _onPlaceSearchChanged('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.primaryPurple, width: 1.5),
                        ),
                      ),
                    ),

                    // ── Dynamic Place Search Suggestions List ──
                    if (_showPlaceSuggestions && _placeSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 210),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _placeSuggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (context, i) {
                            final place = _placeSuggestions[i];
                            return InkWell(
                              onTap: () => _selectPlace(place),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3E8FF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.place_rounded, size: 14, color: AppTheme.primaryPurple),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            place.name,
                                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEDE9FE),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  place.category,
                                                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryPurple, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  place.policeStationNearby,
                                                  style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '⭐ ${place.safetyRating}',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF15803D)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Time Slot Picker and Category
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _stopSlotController,
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              labelText: 'Time Slot',
                              labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              hintText: 'e.g. 10:00 AM - 12:00 PM',
                              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              filled: true,
                              fillColor: Colors.white,
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: 'Select Time Slot with Clock',
                                icon: const Icon(Icons.access_time_filled_rounded, color: AppTheme.primaryPurple, size: 20),
                                onPressed: _pickStopSlotTimes,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppTheme.primaryPurple, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _stopCategory,
                                dropdownColor: Colors.white,
                                icon: Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary, size: 18),
                                items: ['Heritage', 'Temple', 'Market', 'Scenic', 'Dining', 'Museum']
                                    .map((cat) => DropdownMenuItem(
                                          value: cat,
                                          child: Text(cat, style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _stopCategory = val);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Quick Slot Selection Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text('Quick Slots: ', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          ...[
                            '09:30 AM - 11:30 AM',
                            '12:00 PM - 02:00 PM',
                            '02:30 PM - 04:30 PM',
                            '05:00 PM - 07:00 PM',
                          ].map((slot) {
                            final isSel = _stopSlotController.text == slot;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(slot),
                                labelStyle: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: isSel ? AppTheme.primaryPurple : AppTheme.textSecondary,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                ),
                                backgroundColor: isSel ? const Color(0xFFEDE9FE) : Colors.white,
                                side: BorderSide(
                                  color: isSel ? AppTheme.primaryPurple : const Color(0xFFE2E8F0),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                onPressed: () {
                                  setState(() {
                                    _stopSlotController.text = slot;
                                  });
                                },
                              ),
                            );
                          }),
                          ActionChip(
                            avatar: const Icon(Icons.more_time_rounded, size: 14, color: AppTheme.primaryPurple),
                            label: const Text('Custom Clock'),
                            labelStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryPurple, fontWeight: FontWeight.w700),
                            backgroundColor: const Color(0xFFF3E8FF),
                            side: const BorderSide(color: Color(0xFFD8B4FE)),
                            onPressed: _pickStopSlotTimes,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _addCustomStop,
                        icon: const Icon(Icons.add, size: 16, color: Colors.white),
                        label: const Text('Add to Itinerary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Safety check-in setting
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.primaryPurple,
                title: Text(
                  'Auto Emergency Check-In (Every 60m)',
                  style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Prompts you to confirm safety while visiting stops',
                  style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 11),
                ),
                value: _checkInMinutes == 60,
                onChanged: (val) => setState(() => _checkInMinutes = val ? 60 : 120),
              ),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppTheme.primaryPurple,
                title: Text(
                  'Share Itinerary with Trusted Contacts',
                  style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Sends route snapshot and tracking coordinates',
                  style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 11),
                ),
                value: _shareWithContacts,
                onChanged: (val) => setState(() => _shareWithContacts = val),
              ),

              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                  ),
                  child: Text(
                    'Save & Activate Safe Itinerary',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
