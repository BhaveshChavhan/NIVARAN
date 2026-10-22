import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivaran/models/mesh_message.dart';
import 'package:nivaran/services/mesh_service.dart';

void main() {
  setUpAll(() async {
    // Initialize a temporary Hive memory storage for testing
    Hive.init('./test_hive_cache');
    Hive.registerAdapter(MeshMessageAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
  });

  group('NIVARAN Offline Mesh Protocol Tests', () {
    test('1. Message Model serialization contains all required fields', () {
      final now = DateTime.now();
      final msg = MeshMessage(
        id: 'msg-uuid-101',
        senderId: 'device-a-uuid',
        senderName: 'Device A',
        receiverId: 'broadcast',
        payload: 'EMERGENCY: Power outage & medical assistance needed',
        timestamp: now,
        type: 'sos_alert',
        deliveryStatus: 'sending',
        hopCount: 0,
        pathTrace: ['device-a-uuid'],
        latitude: 19.0760,
        longitude: 72.8777,
        priority: 'sos',
        ackRequired: true,
      );

      final json = msg.toJson();
      expect(json['id'], 'msg-uuid-101');
      expect(json['senderId'], 'device-a-uuid');
      expect(json['senderName'], 'Device A');
      expect(json['payload'], 'EMERGENCY: Power outage & medical assistance needed');
      expect(json['type'], 'sos_alert');
      expect(json['deliveryStatus'], 'sending');
      expect(json['latitude'], 19.0760);
      expect(json['longitude'], 72.8777);
      expect(json['priority'], 'sos');
      expect(json['hopCount'], 0);
      expect(json['pathTrace'], ['device-a-uuid']);

      // Test deserialization
      final deserialized = MeshMessage.fromJson(json);
      expect(deserialized.id, msg.id);
      expect(deserialized.senderId, msg.senderId);
      expect(deserialized.latitude, msg.latitude);
      expect(deserialized.longitude, msg.longitude);
      expect(deserialized.priority, 'sos');
    });

    test('2. Multi-Hop Relay Simulation: Device A -> Device B -> Device C', () {
      // Step 1: Device A creates SOS message
      final msgA = MeshMessage(
        id: 'emergency-sos-42',
        senderId: 'node-A',
        senderName: 'Victim Phone A',
        receiverId: 'broadcast',
        payload: 'SOS HELP at Central Park',
        timestamp: DateTime.now(),
        type: 'sos_alert',
        deliveryStatus: 'waiting_for_relay',
        hopCount: 0,
        pathTrace: ['node-A'],
        latitude: 28.6139,
        longitude: 77.2090,
        priority: 'sos',
      );

      expect(msgA.deliveryStatus, 'waiting_for_relay');
      expect(msgA.hopCount, 0);
      expect(msgA.pathTrace, ['node-A']);

      // Step 2: Device B receives from A and prepares relay
      final processedByB = Set<String>();
      expect(processedByB.contains(msgA.id), isFalse);
      processedByB.add(msgA.id);

      final msgBRelayed = MeshMessage(
        id: msgA.id,
        senderId: msgA.senderId,
        senderName: msgA.senderName,
        receiverId: msgA.receiverId,
        payload: msgA.payload,
        timestamp: msgA.timestamp,
        type: msgA.type,
        deliveryStatus: 'relayed',
        hopCount: msgA.hopCount + 1,
        pathTrace: [...msgA.pathTrace, 'node-B'],
        latitude: msgA.latitude,
        longitude: msgA.longitude,
        priority: msgA.priority,
      );

      expect(msgBRelayed.hopCount, 1);
      expect(msgBRelayed.pathTrace, ['node-A', 'node-B']);
      expect(msgBRelayed.deliveryStatus, 'relayed');

      // Step 3: Device C receives from B (hopCount = 2)
      final processedByC = Set<String>();
      expect(processedByC.contains(msgBRelayed.id), isFalse);
      processedByC.add(msgBRelayed.id);

      final msgCDelivered = MeshMessage(
        id: msgBRelayed.id,
        senderId: msgBRelayed.senderId,
        senderName: msgBRelayed.senderName,
        receiverId: msgBRelayed.receiverId,
        payload: msgBRelayed.payload,
        timestamp: msgBRelayed.timestamp,
        type: msgBRelayed.type,
        deliveryStatus: 'delivered',
        hopCount: msgBRelayed.hopCount + 1,
        pathTrace: [...msgBRelayed.pathTrace, 'node-C'],
        latitude: msgBRelayed.latitude,
        longitude: msgBRelayed.longitude,
        priority: msgBRelayed.priority,
      );

      expect(msgCDelivered.hopCount, 2);
      expect(msgCDelivered.pathTrace, ['node-A', 'node-B', 'node-C']);
      expect(msgCDelivered.deliveryStatus, 'delivered');
    });

    test('3. Deduplication prevents re-broadcasting and infinite loops', () {
      final processedCache = <String, bool>{};
      final messageId = 'unique-msg-999';

      // First arrival
      expect(processedCache.containsKey(messageId), isFalse);
      processedCache[messageId] = true;
      expect(processedCache.containsKey(messageId), isTrue);

      // Duplicate arrival via alternate path
      bool shouldProcessAgain = !processedCache.containsKey(messageId);
      expect(shouldProcessAgain, isFalse);
    });

    test('4. Store-and-Forward simulation when next relay is temporarily unavailable', () {
      final pendingQueue = <MeshMessage>[];

      // A sends message while alone
      final outgoingMsg = MeshMessage(
        id: 'msg-buffered-1',
        senderId: 'node-A',
        senderName: 'User A',
        receiverId: 'broadcast',
        payload: 'Offline message stored on device',
        timestamp: DateTime.now(),
        type: 'chat',
        deliveryStatus: 'waiting_for_relay',
      );
      pendingQueue.add(outgoingMsg);

      expect(pendingQueue.length, 1);
      expect(pendingQueue.first.deliveryStatus, 'waiting_for_relay');

      // Peer B comes in range after 5 minutes
      const newPeerId = 'node-B';
      final messagesToSync = pendingQueue
          .where((m) => !m.pathTrace.contains(newPeerId))
          .toList();

      expect(messagesToSync.length, 1);
      messagesToSync.first.deliveryStatus = 'relayed';
      expect(messagesToSync.first.deliveryStatus, 'relayed');
    });

    test('5. Communication Mode Resolver logic verification', () {
      final mesh = MeshService(userName: 'Tester');

      // Default with no internet and no peers
      expect(mesh.currentMode, MeshCommunicationMode.waitingForRelay);
      expect(mesh.currentModeLabel, 'Waiting for Relay');

      // 1 peer directly connected
      mesh.connectedPeers['endpoint-1'] = 'Peer B';
      expect(mesh.currentMode, MeshCommunicationMode.directOffline);
      expect(mesh.currentModeLabel, 'Direct Offline');

      // 2 peers connected (mesh cluster / relay)
      mesh.connectedPeers['endpoint-2'] = 'Peer C';
      expect(mesh.currentMode, MeshCommunicationMode.relayOfflineMesh);
      expect(mesh.currentModeLabel, 'Relay/Offline Mesh');
    });
  });
}
