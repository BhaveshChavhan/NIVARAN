import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/mesh_service.dart';
import '../services/local_storage_service.dart';
import '../theme/app_theme.dart';
import 'mesh_chat_screen.dart';

class MeshNetworkScreen extends StatefulWidget {
  const MeshNetworkScreen({super.key});

  @override
  State<MeshNetworkScreen> createState() => _MeshNetworkScreenState();
}

class _MeshNetworkScreenState extends State<MeshNetworkScreen> {
  @override
  void initState() {
    super.initState();
    _startMesh();
  }

  Future<void> _startMesh() async {
    // Request all permissions needed for Nearby Connections (BLE + Wi-Fi Direct without router)
    final statuses = await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
      Permission.microphone,
    ].request();

    debugPrint('[Mesh] Permission statuses: $statuses');

    // Check location service is on (required by Android OS for BLE / Wi-Fi Direct discovery)
    if (!await Permission.location.serviceStatus.isEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Device Location/GPS for direct phone-to-phone discovery!'),
            backgroundColor: AppTheme.dangerRed,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (!mounted) return;
    final mesh = context.read<MeshService>();
    await mesh.init();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Offline Mesh Network',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E293B),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1E293B)),
        actions: [
          IconButton(
            tooltip: mesh.isAdmin ? 'Admin Gateway Active' : 'Standard User Node',
            icon: Icon(
              mesh.isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
              color: mesh.isAdmin ? AppTheme.accentBlue : AppTheme.textMuted,
            ),
            onPressed: () {
              mesh.toggleAdmin();
            },
          ),
          IconButton(
            tooltip: mesh.isScanning ? 'Scanning Active (Tap to Stop)' : 'Inactive (Tap to Scan)',
            icon: Icon(
              mesh.isScanning ? Icons.sensors_rounded : Icons.sensors_off_rounded,
              color: mesh.isScanning ? AppTheme.safeGreen : AppTheme.dangerRed,
            ),
            onPressed: () async {
              if (mesh.isScanning) {
                await mesh.stopAll();
              } else {
                await _startMesh();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode Banner
            _buildModeHeader(mesh, isDark),

            // Quick Offline Chat Action Card
            _buildChatLauncherCard(context, mesh, isDark),

            // Range & Technology Architecture Card
            _buildArchitectureCard(isDark),

            // Nodes List Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Nearby Nodes & Relays',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${mesh.connectedPeers.length} Connected',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryPurple,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Peers List
            _buildPeersList(context, mesh, isDark),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MeshChatScreen(
                peerId: 'broadcast',
                peerName: 'Offline Emergency Chat',
              ),
            ),
          );
        },
        backgroundColor: AppTheme.primaryPurple,
        icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
        label: const Text(
          'Offline Chat',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildModeHeader(MeshService mesh, bool isDark) {
    Color modeColor;
    IconData modeIcon;
    switch (mesh.currentMode) {
      case MeshCommunicationMode.online:
        modeColor = AppTheme.safeGreen;
        modeIcon = Icons.cloud_done_rounded;
        break;
      case MeshCommunicationMode.directOffline:
        modeColor = AppTheme.accentBlue;
        modeIcon = Icons.wifi_tethering_rounded;
        break;
      case MeshCommunicationMode.relayOfflineMesh:
        modeColor = AppTheme.primaryPurple;
        modeIcon = Icons.hub_rounded;
        break;
      case MeshCommunicationMode.waitingForRelay:
        modeColor = AppTheme.cautionYellow;
        modeIcon = Icons.schedule_send_rounded;
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: modeColor.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: modeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(modeIcon, color: modeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'COMMUNICATION MODE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: modeColor,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: modeColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            mesh.currentModeLabel.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mesh.currentModeLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getModeDescription(mesh.currentMode),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  String _getModeDescription(MeshCommunicationMode mode) {
    switch (mode) {
      case MeshCommunicationMode.online:
        return 'Internet connection active. NIVARAN coordinates both cloud broadcasting and direct offline mesh sync.';
      case MeshCommunicationMode.directOffline:
        return 'Direct phone-to-phone wireless active (Bluetooth Low Energy + Wi-Fi Direct). No router or internet needed.';
      case MeshCommunicationMode.relayOfflineMesh:
        return 'Multi-hop offline mesh active. Messages automatically hop across intermediate NIVARAN devices to reach distant nodes.';
      case MeshCommunicationMode.waitingForRelay:
        return 'No nearby peers detected right now. Messages are stored securely on-device and will auto-forward as soon as another NIVARAN device comes within wireless range.';
    }
  }

  Widget _buildChatLauncherCard(BuildContext context, MeshService mesh, bool isDark) {
    final pendingCount = LocalStorageService.getPendingRelays().length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryPurple.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.forum_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline Emergency Chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pendingCount > 0
                      ? '$pendingCount message${pendingCount > 1 ? 's' : ''} queued for store-and-forward'
                      : 'Send text & SOS offline with GPS coordinates',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryPurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MeshChatScreen(
                    peerId: 'broadcast',
                    peerName: 'Offline Emergency Chat',
                  ),
                ),
              );
            },
            child: const Text('Open Chat', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildArchitectureCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.accentCyan),
              const SizedBox(width: 6),
              Text(
                'Direct Wireless & Multi-Hop Architecture',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '• Transport: Bluetooth Low Energy (10-30m) & Wi-Fi Direct (30-80m).\n'
            '• Multi-Hop: Phone A → Phone B → Phone C relay extends coverage area.\n'
            '• Store-and-Forward: Offline messages buffer locally and sync on contact.\n'
            '• Security: End-to-end AES-256-GCM encryption on every local packet.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeersList(BuildContext context, MeshService mesh, bool isDark) {
    final allPeersId = {...mesh.nearbyEndpoints.keys, ...mesh.connectedPeers.keys}.toList();

    if (allPeersId.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              Icon(
                mesh.isScanning ? Icons.bluetooth_searching_rounded : Icons.sensors_off_rounded,
                size: 40,
                color: mesh.isScanning ? AppTheme.primaryPurple : AppTheme.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                mesh.isScanning ? 'Searching for nearby NIVARAN devices...' : 'Scanning is stopped',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bring another phone with NIVARAN nearby. Devices connect automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: allPeersId.length,
      itemBuilder: (context, index) {
        final id = allPeersId[index];
        final name = mesh.connectedPeers[id] ?? mesh.nearbyEndpoints[id] ?? 'Nivaran Node';
        final isConnected = mesh.connectedPeers.containsKey(id);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isConnected
                  ? AppTheme.safeGreen.withValues(alpha: 0.3)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: isConnected
                  ? AppTheme.safeGreen.withValues(alpha: 0.15)
                  : (isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
              child: Icon(
                Icons.phone_android_rounded,
                color: isConnected ? AppTheme.safeGreen : AppTheme.textMuted,
                size: 20,
              ),
            ),
            title: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            subtitle: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isConnected ? AppTheme.safeGreen : AppTheme.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'Connected Relay' : 'Discovered (Connecting...)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isConnected ? AppTheme.safeGreen : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primaryPurple, size: 20),
              onPressed: () {
                final peerUserId = mesh.endpointToUserId[id] ?? id;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MeshChatScreen(peerId: peerUserId, peerName: name),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
