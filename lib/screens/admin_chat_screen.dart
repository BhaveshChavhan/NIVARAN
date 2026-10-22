import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../services/user_service.dart';
import '../services/safety_service.dart';

class AdminChatScreen extends StatefulWidget {
  final String? initialUserEmail;

  const AdminChatScreen({super.key, this.initialUserEmail});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _isSharingLocation = false;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    final user = context.read<UserService>();
    final email = user.profile?.email;
    _userEmail = widget.initialUserEmail ??
        ((email != null && email.isNotEmpty) ? email : 'bhaavesh9699@gmail.com');
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _textController.text).trim();
    if (text.isEmpty || _isSending) return;

    if (presetText == null) {
      _textController.clear();
    }

    setState(() => _isSending = true);

    try {
      await SupabaseService.sendAdminMessage(
        userEmail: _userEmail,
        message: text,
        isAdmin: false,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _shareLiveLocation() async {
    setState(() => _isSharingLocation = true);
    try {
      final safety = context.read<SafetyService>();
      double lat = safety.currentLat;
      double lng = safety.currentLng;

      if (lat == 0.0 || lng == 0.0) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }

      await SupabaseService.updateUserLocation(
        email: _userEmail,
        lat: lat,
        lng: lng,
      );

      final locationMessage =
          '📍 [LIVE LOCATION SHARED] Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}';
      await _sendMessage(locationMessage);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Live GPS location sent to Admin Dashboard'),
            backgroundColor: AppTheme.safeGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not obtain GPS location: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSharingLocation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: isDark ? Colors.white : const Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primaryPurple.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded,
                  color: AppTheme.primaryPurple, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Admin Support & Broadcast',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.safeGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Direct Cloud Link • Online',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.my_location_rounded,
              color: _isSharingLocation ? AppTheme.accentBlue : AppTheme.primaryPurple,
            ),
            tooltip: 'Share Live Location with Admin',
            onPressed: _isSharingLocation ? null : _shareLiveLocation,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.support_agent_rounded,
                    color: AppTheme.primaryPurple, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Live 24/7 Command Center. All messages are encrypted and monitored by emergency dispatch.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : const Color(0xFF334155),
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick Prompt Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildQuickChip('🚨 I need emergency help',
                    '🚨 Emergency Alert: Please connect with emergency services immediately.'),
                const SizedBox(width: 8),
                _buildQuickChip('📍 Share My Live Location', null,
                    isLocation: true),
                const SizedBox(width: 8),
                _buildQuickChip('🛡️ In Safe Zone',
                    'Update: I have reached a verified Safe Zone safely.'),
                const SizedBox(width: 8),
                _buildQuickChip('⚠️ Suspicious Activity',
                    'Reporting suspicious activity in my immediate vicinity.'),
              ],
            ),
          ),

          // Message Stream
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseService.getAdminMessages(_userEmail),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryPurple),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 48,
                            color: isDark ? Colors.white24 : Colors.black12),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Type below to chat directly with SafeNet Admin.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isAdmin = msg['is_admin'] == true;
                    final text = msg['message']?.toString() ?? '';
                    final createdAt = msg['created_at']?.toString() ?? '';

                    return _buildMessageBubble(
                      text: text,
                      isAdmin: isAdmin,
                      timestamp: createdAt,
                      isDark: isDark,
                    );
                  },
                );
              },
            ),
          ),

          // Input Bar
          _buildInputBar(isDark),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, String? messageToSend,
      {bool isLocation = false}) {
    return ActionChip(
      label: Text(label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      backgroundColor: Colors.white,
      side: BorderSide(color: AppTheme.primaryPurple.withValues(alpha: 0.2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        if (isLocation) {
          _shareLiveLocation();
        } else if (messageToSend != null) {
          _sendMessage(messageToSend);
        }
      },
    );
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isAdmin,
    required String timestamp,
    required bool isDark,
  }) {
    final isMe = !isAdmin;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? AppTheme.primaryPurple
              : (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: isMe
              ? null
              : Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isAdmin)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_rounded,
                      size: 11, color: AppTheme.dangerRed),
                  const SizedBox(width: 4),
                  Text(
                    'SafeNet Admin',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.dangerRed,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            if (isAdmin) const SizedBox(height: 3),
            Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                color: isMe
                    ? Colors.white
                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(timestamp),
              style: TextStyle(
                fontSize: 9.5,
                color: isMe
                    ? Colors.white70
                    : (isDark ? Colors.white38 : Colors.black38),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
              color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Type message to SafeNet Admin...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 13,
                ),
                filled: true,
                fillColor:
                    isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
              onPressed: _isSending ? null : () => _sendMessage(),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $amPm';
    } catch (_) {
      return '';
    }
  }
}
