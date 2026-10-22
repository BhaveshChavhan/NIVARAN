import 'package:hive/hive.dart';

part 'mesh_message.g.dart';

@HiveType(typeId: 0)
class MeshMessage extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String senderId;

  @HiveField(2)
  final String receiverId;

  @HiveField(3)
  final String payload;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final String type; // 'chat', 'call_offer', 'call_answer', 'ice_candidate'

  @HiveField(6)
  String deliveryStatus; // 'pending', 'relayed', 'delivered_to_admin', 'unconfirmed'

  @HiveField(7)
  int hopCount;

  @HiveField(8)
  List<String> pathTrace;

  @HiveField(9)
  bool isEncrypted;

  @HiveField(10)
  final String senderName;

  @HiveField(11)
  final bool ackRequired;

  @HiveField(12)
  double? latitude;

  @HiveField(13)
  double? longitude;

  @HiveField(14)
  String priority; // 'sos', 'high', 'normal'

  @HiveField(15)
  final String? senderEmail;

  MeshMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.payload,
    required this.timestamp,
    required this.type,
    this.deliveryStatus = 'sending',
    this.hopCount = 0,
    this.pathTrace = const [],
    this.isEncrypted = false,
    this.senderName = 'Unknown',
    this.senderEmail,
    this.ackRequired = false,
    this.latitude,
    this.longitude,
    this.priority = 'normal',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'deliveryStatus': deliveryStatus,
      'hopCount': hopCount,
      'pathTrace': pathTrace,
      'isEncrypted': isEncrypted,
      'senderName': senderName,
      'senderEmail': senderEmail,
      'ackRequired': ackRequired,
      'latitude': latitude,
      'longitude': longitude,
      'priority': priority,
    };
  }

  factory MeshMessage.fromJson(Map<String, dynamic> json) {
    return MeshMessage(
      id: json['id'],
      senderId: json['senderId'] ?? 'unknown',
      receiverId: json['receiverId'] ?? 'broadcast',
      payload: json['payload'] ?? '',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
      type: json['type'] ?? 'chat',
      deliveryStatus: json['deliveryStatus'] ?? 'sending',
      hopCount: json['hopCount'] ?? 0,
      pathTrace: List<String>.from(json['pathTrace'] ?? []),
      isEncrypted: json['isEncrypted'] ?? false,
      senderName: json['senderName'] ?? 'Unknown',
      senderEmail: json['senderEmail'],
      ackRequired: json['ackRequired'] ?? false,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      priority: json['priority'] ?? 'normal',
    );
  }
}
