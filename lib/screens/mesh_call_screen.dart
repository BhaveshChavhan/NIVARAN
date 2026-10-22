import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mesh_call_service.dart';
import '../theme/app_theme.dart';

class MeshCallScreen extends StatelessWidget {
  const MeshCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<MeshCallService>();

    if (callService.currentCallEndpointId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: const Center(
          child: Text("Call ended", style: TextStyle(color: Colors.white70, fontSize: 18)),
        ),
      );
    }

    final isIncoming = callService.isIncoming;
    final isActive = callService.isActive;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Header tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? Icons.wifi_tethering_rounded : Icons.sensors_rounded,
                    size: 14,
                    color: isActive ? AppTheme.safeGreen : AppTheme.accentBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isActive
                        ? 'Pure P2P Mesh Call (No Router)'
                        : (isIncoming ? 'Incoming Mesh Call' : 'Connecting Nearby Peer...'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Avatar & Speaking Glow
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  if (callService.isRemoteSpeaking)
                    BoxShadow(
                      color: AppTheme.safeGreen.withValues(alpha: 0.4),
                      blurRadius: 35,
                      spreadRadius: 8,
                    )
                  else if (callService.isLocalSpeaking)
                    BoxShadow(
                      color: AppTheme.primaryPurple.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 6,
                    ),
                ],
              ),
              child: CircleAvatar(
                radius: 64,
                backgroundColor: AppTheme.primaryPurple.withValues(alpha: 0.25),
                child: const Icon(Icons.person, size: 68, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),

            // Peer Name
            Text(
              callService.currentCallPeerName ?? 'Nearby Peer',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),

            // Call Status / Duration / Speaking indicators
            if (isActive) ...[
              Text(
                callService.formattedDuration,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              if (callService.isRemoteSpeaking)
                const Text(
                  '🔊 Peer is speaking...',
                  style: TextStyle(fontSize: 13, color: AppTheme.safeGreen, fontWeight: FontWeight.w600),
                )
              else if (callService.isLocalSpeaking)
                const Text(
                  '🎙️ Streaming voice...',
                  style: TextStyle(fontSize: 13, color: AppTheme.accentCyan, fontWeight: FontWeight.w600),
                )
              else
                const Text(
                  'Direct offline voice stream active',
                  style: TextStyle(fontSize: 13, color: Colors.white38),
                ),
            ] else ...[
              Text(
                isIncoming ? 'Incoming Call...' : 'Calling via P2P Mesh...',
                style: const TextStyle(fontSize: 16, color: Colors.white60),
              ),
            ],

            const Spacer(),

            // Push-to-Talk Button (Walkie-Talkie Mode)
            if (isActive) ...[
              GestureDetector(
                onTapDown: (_) => callService.startPushToTalk(),
                onTapUp: (_) => callService.stopPushToTalk(),
                onTapCancel: () => callService.stopPushToTalk(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: callService.isLocalSpeaking
                        ? AppTheme.accentCyan.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: callService.isLocalSpeaking ? AppTheme.accentCyan : Colors.white24,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic,
                        color: callService.isLocalSpeaking ? AppTheme.accentCyan : Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        callService.isLocalSpeaking ? 'TRANSMITTING VOICE...' : 'HOLD TO TALK (PTT)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: callService.isLocalSpeaking ? AppTheme.accentCyan : Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],

            // Action Buttons
            if (isIncoming) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallButton(
                    icon: Icons.call,
                    color: AppTheme.safeGreen,
                    label: 'Accept',
                    onPressed: () => callService.acceptCall(),
                  ),
                  _buildCallButton(
                    icon: Icons.call_end,
                    color: AppTheme.dangerRed,
                    label: 'Decline',
                    onPressed: () => callService.endCall(),
                  ),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSecondaryButton(
                    icon: callService.isMuted ? Icons.mic_off : Icons.mic,
                    color: callService.isMuted ? Colors.redAccent : Colors.white60,
                    label: callService.isMuted ? 'Muted' : 'Mute',
                    onPressed: () => callService.toggleMute(),
                  ),
                  _buildCallButton(
                    icon: Icons.call_end,
                    color: AppTheme.dangerRed,
                    label: 'End Call',
                    onPressed: () => callService.endCall(),
                  ),
                  _buildSecondaryButton(
                    icon: callService.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    color: callService.isSpeakerOn ? AppTheme.safeGreen : Colors.white60,
                    label: 'Speaker',
                    onPressed: () => callService.toggleSpeaker(),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ],
    );
  }
}
