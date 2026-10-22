import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../models/mesh_message.dart';
import '../services/mesh_service.dart';
import '../services/local_storage_service.dart';
import '../services/safety_service.dart';
import '../theme/app_theme.dart';
import '../services/mesh_call_service.dart';
import 'mesh_call_screen.dart';
import 'admin_chat_screen.dart';

class MeshChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;

  const MeshChatScreen({
    super.key,
    this.peerId = 'broadcast',
    this.peerName = 'Offline Emergency Chat',
  });

  @override
  State<MeshChatScreen> createState() => _MeshChatScreenState();
}

class _MeshChatScreenState extends State<MeshChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<MeshMessage>? _chatMessageSub;
  bool _attachLocation = true;
  bool _isEmergencyPriority = false;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Instant live listener for incoming mesh messages
    final mesh = context.read<MeshService>();
    _chatMessageSub = mesh.chatMessageStream.listen((msg) {
      if (!mounted) return;
      final peerEndpointId = mesh.userIdToEndpoint[widget.peerId] ?? '';
      final peerUserId = mesh.endpointToUserId[widget.peerId] ?? widget.peerId;
      final relevantIds = {widget.peerId, peerEndpointId, peerUserId, 'broadcast'};

      if (widget.peerId == 'broadcast' ||
          relevantIds.contains(msg.senderId) ||
          relevantIds.contains(msg.receiverId)) {
        setState(() {});
        Future.delayed(const Duration(milliseconds: 50), _scrollToBottom);
      }
    });
  }

  @override
  void dispose() {
    _chatMessageSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = context.watch<MeshService>();
    final isGroup = widget.peerId == 'broadcast';

    // Resolve endpoint and user UUID bidirectionally
    final peerEndpointId = mesh.userIdToEndpoint[widget.peerId] ??
        (mesh.connectedPeers.containsKey(widget.peerId) ? widget.peerId : null);
    final peerUserId = mesh.endpointToUserId[widget.peerId] ?? widget.peerId;

    // Retrieve offline messages from local storage
    final List<MeshMessage> messages = isGroup
        ? LocalStorageService.getEmergencyChatMessages()
        : LocalStorageService.getMessagesFor(widget.peerId, [peerEndpointId ?? '', peerUserId]);

    final isDirectlyConnected = peerEndpointId != null && mesh.connectedPeers.containsKey(peerEndpointId);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGroup ? 'Offline Emergency Chat' : widget.peerName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                _buildModeDot(mesh.currentMode),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    mesh.currentModeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _getModeColor(mesh.currentMode),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isGroup && mesh.connectedPeers.isNotEmpty) ...[
                  Text(
                    ' • ${mesh.connectedPeers.length} peer${mesh.connectedPeers.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : const Color(0xFF1E293B)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms_rounded, color: AppTheme.cautionYellow),
            tooltip: 'Offline 2G SMS Dispatch (No App Needed)',
            onPressed: () => _openOfflineSMSModal(prefilledMessage: _messageController.text),
          ),
          if (!isGroup && peerEndpointId != null && isDirectlyConnected)
            IconButton(
              icon: const Icon(Icons.call_rounded, color: AppTheme.safeGreen),
              tooltip: 'Direct P2P Call',
              onPressed: () {
                context.read<MeshCallService>().startCall(peerEndpointId);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MeshCallScreen()));
              },
            ),
          IconButton(
            icon: const Icon(Icons.support_agent_rounded, color: AppTheme.primaryPurple),
            tooltip: 'Live Admin Support Chat',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminChatScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Offline Queue',
            onPressed: () async {
              await mesh.syncPendingMessagesNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Store-and-forward sync triggered (${LocalStorageService.getPendingRelays().length} queued)',
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Communication Mode Banner
          _buildCommunicationModeBanner(mesh, isDark),

          // Chat Messages List
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(mesh, isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildMessageBubble(msg, mesh.userId, isDark);
                    },
                  ),
          ),

          // Message Input Bar
          _buildMessageInput(mesh, isDark),
        ],
      ),
    );
  }

  // ─── Communication Mode Banner ──────────────────────────────────────────

  Widget _buildCommunicationModeBanner(MeshService mesh, bool isDark) {
    final mode = mesh.currentMode;
    final modeColor = _getModeColor(mode);
    IconData modeIcon;
    String modeTitle;
    String modeDescription;

    switch (mode) {
      case MeshCommunicationMode.online:
        modeIcon = Icons.cloud_done_rounded;
        modeTitle = 'Online Mode Active';
        modeDescription = 'Connected to Internet & NIVARAN offline mesh. Cloud sync and direct P2P enabled.';
        break;
      case MeshCommunicationMode.directOffline:
        modeIcon = Icons.wifi_tethering_rounded;
        modeTitle = 'Direct Offline Active';
        modeDescription = 'Direct phone-to-phone via Bluetooth & Wi-Fi Direct. No router or cellular required.';
        break;
      case MeshCommunicationMode.relayOfflineMesh:
        modeIcon = Icons.hub_rounded;
        modeTitle = 'Relay / Offline Mesh Active';
        modeDescription = 'Multi-hop relay forwarding packets through intermediate NIVARAN devices.';
        break;
      case MeshCommunicationMode.waitingForRelay:
        modeIcon = Icons.sensors_off_rounded;
        modeTitle = 'Waiting for Relay';
        modeDescription = 'No peers currently in range. Outgoing messages stored securely; auto-forwarding on detection.';
        break;
    }

    final queuedCount = LocalStorageService.getPendingRelays().length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: modeColor.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: modeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(modeIcon, color: modeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            modeTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: modeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            mesh.currentModeLabel.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      modeDescription,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                        height: 1.3,
                      ),
                    ),
                    if (queuedCount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 12, color: modeColor),
                          const SizedBox(width: 4),
                          Text(
                            '$queuedCount message${queuedCount > 1 ? 's' : ''} stored locally waiting for relay handoff',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: modeColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (mode == MeshCommunicationMode.waitingForRelay || mesh.connectedPeers.isEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.cautionYellow.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.cautionYellow.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mark_chat_unread_rounded, size: 18, color: AppTheme.cautionYellow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No app users nearby? Recipient does NOT need the app to receive 2G SMS alerts.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cautionYellow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                      visualDensity: VisualDensity.compact,
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 12),
                    label: const Text('SMS Fallback'),
                    onPressed: () => _openOfflineSMSModal(prefilledMessage: _messageController.text),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeDot(MeshCommunicationMode mode) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: _getModeColor(mode),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _getModeColor(MeshCommunicationMode mode) {
    switch (mode) {
      case MeshCommunicationMode.online:
        return AppTheme.safeGreen;
      case MeshCommunicationMode.directOffline:
        return AppTheme.accentBlue;
      case MeshCommunicationMode.relayOfflineMesh:
        return AppTheme.primaryPurple;
      case MeshCommunicationMode.waitingForRelay:
        return AppTheme.cautionYellow;
    }
  }

  // ─── Empty State ──────────────────────────────────────────────────────────

  Widget _buildEmptyState(MeshService mesh, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_chat_unread_rounded,
                size: 48,
                color: AppTheme.primaryPurple,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Emergency Messages Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Messages sent here broadcast directly to nearby NIVARAN devices without needing an internet connection, cellular signal, or Wi-Fi router.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Message Bubble ───────────────────────────────────────────────────────

  Widget _buildMessageBubble(MeshMessage msg, String myId, bool isDark) {
    final isMe = msg.senderId == myId;
    final isSOS = msg.priority == 'sos' || msg.type == 'sos_alert';
    final isHighPriority = msg.priority == 'high';

    Color bubbleBg;
    if (isSOS) {
      bubbleBg = isMe
          ? AppTheme.dangerRed
          : (isDark ? const Color(0xFF4A151B) : const Color(0xFFFFECEE));
    } else if (isMe) {
      bubbleBg = AppTheme.primaryPurple;
    } else {
      bubbleBg = isDark ? AppTheme.darkCard : Colors.white;
    }

    final textColor = (isMe || (isSOS && isDark)) ? Colors.white : (isDark ? Colors.white : const Color(0xFF1E293B));
    final subColor = (isMe || (isSOS && isDark)) ? Colors.white70 : (isDark ? Colors.white60 : const Color(0xFF64748B));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActionSheet(msg),
        child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isSOS
              ? Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.6), width: 1.5)
              : (isDark ? null : Border.all(color: Colors.black.withValues(alpha: 0.05))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Priority Tag & Sender Name
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSOS) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerRed,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 10, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'SOS PRIORITY',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else if (isHighPriority) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.cautionYellow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'HIGH PRIORITY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    isMe ? 'You' : msg.senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isMe ? Colors.white.withValues(alpha: 0.9) : (isDark ? AppTheme.accentCyan : AppTheme.primaryPurple),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Message Body Text
            Text(
              msg.payload,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.3),
            ),

            // GPS Location Attachment Chip
            if (msg.latitude != null && msg.longitude != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isMe ? Colors.white.withValues(alpha: 0.15) : (isDark ? Colors.black26 : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: isMe ? Colors.white : AppTheme.dangerRed,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'GPS: ${msg.latitude!.toStringAsFixed(4)}, ${msg.longitude!.toStringAsFixed(4)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Footer: Timestamp, Hop Count & Delivery Status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 10, color: subColor),
                ),

                // Multi-hop path indicator
                if (msg.hopCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '• ${msg.hopCount} hop${msg.hopCount > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 10, color: subColor, fontStyle: FontStyle.italic),
                  ),
                ],

                // Delivery Status for sent messages
                if (isMe) ...[
                  const SizedBox(width: 6),
                  _buildDeliveryStatusIcon(msg.deliveryStatus, subColor),
                ],
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ─── Delivery Status Icon & Label (Requirement 9) ─────────────────────────

  Widget _buildDeliveryStatusIcon(String status, Color defaultColor) {
    switch (status) {
      case 'sending':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: defaultColor),
            ),
            const SizedBox(width: 4),
            Text('Sending', style: TextStyle(fontSize: 9, color: defaultColor)),
          ],
        );

      case 'waiting_for_relay':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_send_rounded, size: 12, color: AppTheme.cautionYellow),
            const SizedBox(width: 3),
            const Text(
              'Waiting for relay',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.cautionYellow),
            ),
          ],
        );

      case 'relayed':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub_rounded, size: 12, color: Colors.white70),
            const SizedBox(width: 3),
            Text('Relayed', style: TextStyle(fontSize: 9, color: defaultColor)),
          ],
        );

      case 'delivered':
      case 'delivered_to_admin':
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded, size: 14, color: AppTheme.safeGreen),
            SizedBox(width: 3),
            Text(
              'Delivered',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.safeGreen),
            ),
          ],
        );

      default:
        return Icon(Icons.check_rounded, size: 12, color: defaultColor);
    }
  }

  // ─── Message Input Box ────────────────────────────────────────────────────

  Widget _buildMessageInput(MeshService mesh, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggles row: GPS Location attach, SOS Emergency priority & SMS Fallback
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                FilterChip(
                  selected: _attachLocation,
                  avatar: Icon(
                    Icons.my_location_rounded,
                    size: 14,
                    color: _attachLocation ? Colors.white : AppTheme.accentBlue,
                  ),
                  label: const Text('Attach GPS Location', style: TextStyle(fontSize: 11)),
                  selectedColor: AppTheme.accentBlue,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _attachLocation ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (val) {
                    setState(() => _attachLocation = val);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _isEmergencyPriority,
                  avatar: Icon(
                    Icons.emergency_rounded,
                    size: 14,
                    color: _isEmergencyPriority ? Colors.white : AppTheme.dangerRed,
                  ),
                  label: const Text('SOS Priority', style: TextStyle(fontSize: 11)),
                  selectedColor: AppTheme.dangerRed,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _isEmergencyPriority ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (val) {
                    setState(() => _isEmergencyPriority = val);
                  },
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.sms_rounded, size: 14, color: AppTheme.cautionYellow),
                  label: const Text(
                    'SMS (No App)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.cautionYellow,
                    ),
                  ),
                  backgroundColor: AppTheme.cautionYellow.withValues(alpha: isDark ? 0.2 : 0.1),
                  side: BorderSide(color: AppTheme.cautionYellow.withValues(alpha: 0.5)),
                  onPressed: () => _openOfflineSMSModal(prefilledMessage: _messageController.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Text Field, SMS Quick Button, and Send Button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _isEmergencyPriority
                        ? '🚨 Enter urgent emergency SOS message...'
                        : 'Type offline emergency message...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Dedicated SMS Dispatch Button for non-app recipients
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cautionYellow.withValues(alpha: isDark ? 0.2 : 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.cautionYellow.withValues(alpha: 0.4)),
                ),
                child: IconButton(
                  tooltip: 'Dispatch via Offline 2G SMS (No App Required)',
                  icon: const Icon(Icons.sms_rounded, color: AppTheme.cautionYellow, size: 20),
                  onPressed: () => _openOfflineSMSModal(prefilledMessage: _messageController.text),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: _isEmergencyPriority ? AppTheme.sosGradient : AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  onPressed: () => _sendMessage(mesh),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Send Message Action ──────────────────────────────────────────────────

  Future<void> _sendMessage(MeshService mesh) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    double? lat;
    double? lng;

    if (_attachLocation) {
      try {
        final safety = context.read<SafetyService>();
        if (safety.currentLat != 0.0) {
          lat = safety.currentLat;
          lng = safety.currentLng;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 3),
            ),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (_) {}
    }

    final msg = MeshMessage(
      id: const Uuid().v4(),
      senderId: mesh.userId,
      senderName: mesh.userName,
      senderEmail: mesh.userEmail,
      receiverId: widget.peerId,
      payload: text,
      timestamp: DateTime.now(),
      type: _isEmergencyPriority ? 'sos_alert' : 'chat',
      ackRequired: true,
      latitude: lat,
      longitude: lng,
      priority: _isEmergencyPriority ? 'sos' : 'normal',
    );

    if (widget.peerId == 'broadcast') {
      await mesh.broadcastMessage(msg);
    } else {
      await mesh.sendDirectMessage(widget.peerId, msg);
    }

    // Auto-fallback prompt: If sending an SOS message when no peers are in range,
    // prompt immediate SMS fallback so non-app users and contacts are alerted right away
    if (_isEmergencyPriority && mesh.connectedPeers.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.dangerRed,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 7),
          content: const Row(
            children: [
              Icon(Icons.sensors_off_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SOS queued in Mesh (0 peers nearby). Want to dispatch via Offline SMS too?',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'DISPATCH SMS',
            textColor: Colors.yellowAccent,
            onPressed: () => _openOfflineSMSModal(
              prefilledMessage: text,
              attachGps: lat != null,
            ),
          ),
        ),
      );
    }

    _scrollToBottom();
  }

  // ─── Message Long-Press Sheet ─────────────────────────────────────────────

  void _showMessageActionSheet(MeshMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.cautionYellow,
                  child: Icon(Icons.sms_rounded, color: Colors.black, size: 20),
                ),
                title: const Text('Dispatch via Offline 2G SMS', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Send to emergency contacts without needing the app on their phone', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openOfflineSMSModal(
                    prefilledMessage: msg.payload,
                    attachGps: msg.latitude != null && msg.longitude != null,
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.15),
                  child: const Icon(Icons.copy_rounded, color: AppTheme.accentBlue, size: 20),
                ),
                title: const Text('Copy Message Text & Coordinates', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Copy to clipboard for manual sharing', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  final copyText = (msg.latitude != null && msg.longitude != null)
                      ? '${msg.payload}\nGPS: ${msg.latitude}, ${msg.longitude}\nhttps://maps.google.com/?q=${msg.latitude},${msg.longitude}'
                      : msg.payload;
                  Clipboard.setData(ClipboardData(text: copyText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Message and coordinates copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ─── Offline SMS Dispatch Modal (No App Required) ─────────────────────────

  Future<void> _openOfflineSMSModal({
    String? prefilledMessage,
    bool attachGps = true,
    String? specificContactPhone,
  }) async {
    final safety = context.read<SafetyService>();
    final mesh = context.read<MeshService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double lat = safety.currentLat;
    double lng = safety.currentLng;
    if (lat == 0.0 && attachGps) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 3),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}
    }

    final String locationUrl = (lat != 0.0 && lng != 0.0)
        ? 'https://maps.google.com/?q=$lat,$lng'
        : '';

    final defaultText = (prefilledMessage != null && prefilledMessage.trim().isNotEmpty)
        ? prefilledMessage.trim()
        : '🚨 EMERGENCY ALERT: ${mesh.userName} needs urgent assistance!';

    final fullMessage = locationUrl.isNotEmpty
        ? '$defaultText\nLive GPS: $lat, $lng\nMap: $locationUrl'
        : defaultText;

    final smsTextController = TextEditingController(text: fullMessage);
    final customPhoneController = TextEditingController();
    if (specificContactPhone != null) {
      customPhoneController.text = specificContactPhone;
    }

    final selectedPhones = <String>{};
    for (final c in safety.emergencyContacts) {
      if (c.phone.trim().isNotEmpty) {
        selectedPhones.add(c.phone.trim());
      }
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final mediaPadding = MediaQuery.of(modalCtx).viewInsets.bottom;
            return Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, mediaPadding + 20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
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
                            color: AppTheme.cautionYellow.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sms_rounded, color: AppTheme.cautionYellow, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Offline SMS Dispatch (2G/GSM)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Recipient does NOT need the app or internet',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Info Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentBlue.withValues(alpha: isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.cell_tower_rounded, color: AppTheme.accentBlue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'When no one nearby has NIVARAN, SMS transmits directly over cellular base stations to native inboxes.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Recipients section
                    Text(
                      'RECIPIENTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white60 : Colors.black54,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (safety.emergencyContacts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'No saved emergency contacts found. Enter a phone number below or dial 112 directly.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: safety.emergencyContacts.map((contact) {
                          final phone = contact.phone.trim();
                          final isSelected = selectedPhones.contains(phone);
                          return FilterChip(
                            selected: isSelected,
                            avatar: Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.person_outline_rounded,
                              size: 16,
                              color: isSelected ? Colors.white : AppTheme.primaryPurple,
                            ),
                            label: Text(
                              '${contact.name} (${contact.phone})',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white : const Color(0xFF1E293B)),
                              ),
                            ),
                            selectedColor: AppTheme.primaryPurple,
                            checkmarkColor: Colors.white,
                            onSelected: (val) {
                              setModalState(() {
                                if (val) {
                                  selectedPhones.add(phone);
                                } else {
                                  selectedPhones.remove(phone);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 10),

                    // Custom phone / Helpline row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customPhoneController,
                            keyboardType: TextInputType.phone,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              hintText: 'Or custom phone number (e.g. +91...)',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              filled: true,
                              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.local_police_rounded, size: 14, color: AppTheme.dangerRed),
                          label: const Text('112', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.dangerRed)),
                          backgroundColor: AppTheme.dangerRed.withValues(alpha: isDark ? 0.2 : 0.1),
                          side: BorderSide(color: AppTheme.dangerRed.withValues(alpha: 0.4)),
                          onPressed: () {
                            setModalState(() {
                              customPhoneController.text = '112';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // SMS Message Body
                    Text(
                      'SMS MESSAGE CONTENT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white60 : Colors.black54,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: smsTextController,
                      maxLines: 4,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Dispatch Buttons
                    Row(
                      children: [
                        // Button 1: Background SMS
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.cautionYellow,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.flash_on_rounded, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Instant Silent SMS',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                            onPressed: () async {
                              final textToSend = smsTextController.text.trim();
                              if (textToSend.isEmpty) return;

                              final customPhone = customPhoneController.text.trim();
                              final recipients = List<String>.from(selectedPhones);
                              if (customPhone.isNotEmpty && !recipients.contains(customPhone)) {
                                recipients.add(customPhone);
                              }

                              if (recipients.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please select or enter at least one recipient phone number.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }

                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(ctx);

                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('⚡ Sending background SMS to ${recipients.length} recipient(s)...'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: AppTheme.darkCard,
                                ),
                              );

                              for (final phone in recipients) {
                                await safety.sendNativeSMSAlerts(
                                  customMessage: textToSend,
                                  specificPhone: phone,
                                  openMessenger: false,
                                );
                              }

                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('✅ Offline SMS dispatched to ${recipients.length} phone(s)!'),
                                    backgroundColor: AppTheme.safeGreen,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Button 2: Open SMS App
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded, size: 18),
                            label: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Open in SMS App',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            onPressed: () async {
                              final textToSend = smsTextController.text.trim();
                              final customPhone = customPhoneController.text.trim();
                              final recipients = List<String>.from(selectedPhones);
                              if (customPhone.isNotEmpty && !recipients.contains(customPhone)) {
                                recipients.add(customPhone);
                              }

                              Navigator.pop(ctx);

                              await safety.sendNativeSMSAlerts(
                                customMessage: textToSend,
                                specificPhone: recipients.isNotEmpty ? recipients.join(',') : null,
                                openMessenger: true,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
