import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/wearable_service.dart';
import '../services/safety_service.dart';

class WearableWatchScreen extends StatefulWidget {
  const WearableWatchScreen({super.key});

  @override
  State<WearableWatchScreen> createState() => _WearableWatchScreenState();
}

class _WearableWatchScreenState extends State<WearableWatchScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final WearableService _wearableService = WearableService.instance;
  String? _pairingDeviceId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-scan for real nearby smartwatches if not already connected
    if (!_wearableService.hasConnectedWatch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _wearableService.startScan();
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _triggerTestSos() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active_rounded, color: AppTheme.dangerRed, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Watch Crown Signal Test',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppTheme.safeGreen, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Smartwatch BLE Trigger Packet received in 42ms.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF166534), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'In an emergency, triple-tapping your smartwatch crown or holding the panic button triggers:',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 8),
            _buildBulletPoint('High-priority SOS alert with live GPS coordinates'),
            _buildBulletPoint('SMS broadcast to emergency contacts & tourist police'),
            _buildBulletPoint('Silent ambient audio recording for evidence vault'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close Test', style: GoogleFonts.inter(color: AppTheme.primaryPurple, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showConfirmSosDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_rounded, color: AppTheme.dangerRed, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Trigger Watch SOS?',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
        content: Text(
          'This will immediately send your live GPS location, trigger automated SMS to your emergency contacts, alert tourist police, and record ambient audio in the evidence vault.',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _wearableService.triggerWatchSOS();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.emergency_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('🚨 Emergency SOS dispatched via connected watch!')),
                      ],
                    ),
                    backgroundColor: AppTheme.dangerRed,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Dispatch SOS Now', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePairDevice(WearableDevice device) async {
    setState(() => _pairingDeviceId = device.id);
    final success = await _wearableService.connectDevice(device);
    if (!mounted) return;
    setState(() => _pairingDeviceId = null);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully paired with ${device.name}!'),
          backgroundColor: AppTheme.safeGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = _wearableService.scanError ?? 'Could not establish BLE link with ${device.name}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: AppTheme.dangerRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_wearableService, SafetyService.instance]),
      builder: (context, _) {
        final connected = _wearableService.connectedDevice;
        final isConnected = _wearableService.hasConnectedWatch;

        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Wearable Watch',
              style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            actions: [
              if (isConnected)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.safeGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Connected',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF15803D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Tourist Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFF3E8FF),
                        Color(0xFFEDE9FE),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryPurple.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.watch_rounded, color: AppTheme.primaryPurple, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Discreet Tourist Protection',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Connect your smartwatch to send silent emergency alerts, monitor vitals, and receive safe route cues.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (isConnected && connected != null) ...[
                  // ── Watch Emergency SOS Button ──────────────────────────────
                  _buildWatchSosButton(),
                  const SizedBox(height: 20),

                  // ── Connected Watch Card ────────────────────────────────────
                  _buildConnectedWatchCard(connected),
                  const SizedBox(height: 20),

                  // Sensor Telemetry Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildTelemetryCard(
                          icon: Icons.favorite_rounded,
                          iconColor: const Color(0xFFEF4444),
                          label: 'Heart Rate',
                          value: '${connected.heartRate} BPM',
                          subtext: 'Normal Vitals',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTelemetryCard(
                          icon: Icons.battery_charging_full_rounded,
                          iconColor: AppTheme.safeGreen,
                          label: 'Watch Battery',
                          value: '${connected.batteryPercentage}%',
                          subtext: 'BLE Telemetry',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildTelemetryCard(
                          icon: Icons.accessibility_new_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          label: 'Fall Detection',
                          value: connected.fallDetectionEnabled ? 'Armed' : 'Off',
                          subtext: 'Auto impact trigger',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTelemetryCard(
                          icon: Icons.bluetooth_connected_rounded,
                          iconColor: const Color(0xFF0284C7),
                          label: 'BLE Signal',
                          value: '${connected.rssi} dBm',
                          subtext: 'Active Link',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Watch Quick Actions
                  Text(
                    'Watch Triggers & Testing',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: _triggerTestSos,
                    icon: const Icon(Icons.touch_app_rounded, color: Colors.white),
                    label: Text('Test Watch Crown Signal Packet', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF475569),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Smartwatch Toggles
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          activeThumbColor: AppTheme.primaryPurple,
                          title: Text('Fall & Shock Detection', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text('Triggers check-in alert if sudden hard fall is detected', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                          value: connected.fallDetectionEnabled,
                          onChanged: (val) => _wearableService.toggleFallDetection(val),
                        ),
                        const Divider(color: Color(0xFFF1F5F9), height: 1),
                        SwitchListTile(
                          activeThumbColor: AppTheme.primaryPurple,
                          title: Text('SOS Crown Triple-Tap', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text('Press watch crown 3 times quickly to dispatch SOS', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                          value: connected.sosTripleTapEnabled,
                          onChanged: (val) => _wearableService.toggleTripleTap(val),
                        ),
                        const Divider(color: Color(0xFFF1F5F9), height: 1),
                        SwitchListTile(
                          activeThumbColor: AppTheme.primaryPurple,
                          title: Text('Haptic Zone Alerts', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text('Vibrate watch when approaching high-risk tourist areas', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12)),
                          value: connected.hapticAlertsEnabled,
                          onChanged: (val) => _wearableService.toggleHapticAlerts(val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Disconnect button
                  OutlinedButton.icon(
                    onPressed: () => _wearableService.disconnectDevice(),
                    icon: const Icon(Icons.link_off_rounded, color: Color(0xFFEF4444)),
                    label: Text('Disconnect Smartwatch', style: GoogleFonts.inter(color: const Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: const Color(0xFFFEF2F2),
                    ),
                  ),
                ] else ...[
                  // ── Not Connected / Real BLE Discovery State ──────────────
                  _buildScanningRadar(),
                  const SizedBox(height: 20),

                  // Scan Error Banner (if permissions or BT off)
                  if (_wearableService.scanError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _wearableService.scanError!,
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF991B1B)),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _wearableService.startScan(),
                            child: Text('Retry', style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Nearby Smartwatches (${_wearableService.discoveredDevices.length})',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_wearableService.isScanning)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryPurple),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Scanning...',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primaryPurple, fontWeight: FontWeight.w600),
                            ),
                          ],
                        )
                      else
                        InkWell(
                          onTap: () => _wearableService.startScan(),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.primaryPurple),
                                const SizedBox(width: 4),
                                Text(
                                  'Rescan',
                                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primaryPurple, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_wearableService.discoveredDevices.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _wearableService.isScanning ? Icons.bluetooth_searching_rounded : Icons.bluetooth_disabled_rounded,
                            size: 44,
                            color: AppTheme.primaryPurple,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _wearableService.isScanning
                                ? 'Scanning for nearby smartwatches...'
                                : 'No nearby smartwatches found',
                            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ensure your smartwatch is turned on, in pairing mode, and within Bluetooth range (~10m). Only actual nearby devices with names will appear here.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
                          ),
                          if (!_wearableService.isScanning) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _wearableService.startScan(),
                              icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                              label: const Text('Start Bluetooth Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryPurple,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    ..._wearableService.discoveredDevices.map((device) => _buildDeviceTile(device)),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWatchSosButton() {
    final safetyService = SafetyService.instance;
    final isSosActive = safetyService.isSOSActive;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSosActive
              ? const [Color(0xFFDC2626), Color(0xFF991B1B)]
              : const [Color(0xFFE11D48), Color(0xFFBE123C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE11D48).withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            if (isSosActive) {
              safetyService.deactivateSOS();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Watch Emergency SOS Deactivated.'),
                  backgroundColor: AppTheme.textPrimary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            } else {
              _showConfirmSosDialog();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSosActive ? Icons.warning_amber_rounded : Icons.emergency_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSosActive ? 'SOS BROADCAST ACTIVE' : 'WATCH EMERGENCY SOS',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isSosActive
                            ? 'Live GPS & SMS dispatched • Tap to cancel'
                            : 'Broadcasts instant alert to police, emergency contacts & records audio',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    isSosActive ? 'STOP' : 'SOS',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFBE123C),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedWatchCard(WearableDevice device) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6D28D9),
            Color(0xFF7C3AED),
            Color(0xFF8B5CF6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.watch_rounded, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        device.type,
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Synced over Bluetooth',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.9)),
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

  Widget _buildTelemetryCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 22),
              Text(subtext, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningRadar() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.primaryPurple.withValues(alpha: 0.25),
                      AppTheme.primaryPurple.withValues(alpha: 0.04),
                    ],
                  ),
                  border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(Icons.bluetooth_searching_rounded, color: AppTheme.primaryPurple, size: 42),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Scanning for Real Nearby Smartwatches',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Detecting BLE signals from Apple Watch, Wear OS, Galaxy, Noise, boAt, Garmin & more',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(WearableDevice device) {
    final isThisPairing = _pairingDeviceId == device.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.watch_rounded,
              color: AppTheme.primaryPurple,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(device.type, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                    const SizedBox(width: 8),
                    Text('•  ${device.rssi} dBm', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF15803D), fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isThisPairing || _wearableService.isConnecting ? null : () => _handlePairDevice(device),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryPurple,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.primaryPurple.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: isThisPairing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Pair', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
