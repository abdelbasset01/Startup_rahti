import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class MessageBadge extends StatelessWidget {
  final Widget child;
  final bool isDriverMode;

  const MessageBadge({super.key, required this.child, this.isDriverMode = false});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return child;

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref().child('trips').onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return child;
        }

        final tripsData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        final participantTripIds = <String>{};

        tripsData.forEach((tripId, value) {
          final tripMap = Map<String, dynamic>.from(value);
          final status = tripMap['status']?.toString() ?? '';
          if (!(status == 'active' || status == 'full' || status == 'started' || status == 'ongoing')) {
            return;
          }
          bool isParticipant = false;

          if (isDriverMode) {
            if (tripMap['driverId'] == currentUserId) isParticipant = true;
          } else {
            final seats = tripMap['seats'] as Map<dynamic, dynamic>?;
            if (seats != null) {
              for (final seatVal in seats.values) {
                final seatMap = seatVal as Map<dynamic, dynamic>;
                if (seatMap['reservedBy'] == currentUserId) {
                  isParticipant = true;
                  break;
                }
              }
            }
            final takenSeats = tripMap['takenSeats'] as Map<dynamic, dynamic>?;
            if (!isParticipant && takenSeats != null) {
              for (var seatVal in takenSeats.values) {
                final seatMap = seatVal as Map<dynamic, dynamic>;
                if (seatMap['userId'] == currentUserId) {
                  isParticipant = true;
                  break;
                }
              }
            }
          }

          if (isParticipant) {
            participantTripIds.add(tripId.toString());
          }
        });

        if (participantTripIds.isEmpty) return child;

        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref().child('chats').onValue,
          builder: (context, chatSnap) {
            if (!chatSnap.hasData || chatSnap.data?.snapshot.value == null) {
              return child;
            }
            int totalUnread = 0;
            final chats = chatSnap.data!.snapshot.value as Map<dynamic, dynamic>;
            for (final tripId in participantTripIds) {
              final tripChat = chats[tripId] as Map<dynamic, dynamic>?;
              if (tripChat == null) continue;
              final deleted = tripChat['deletedChats'] as Map<dynamic, dynamic>?;
              if (deleted != null && deleted[currentUserId] == true) continue;
              final clearedAt = ((tripChat['clearedAt'] as Map<dynamic, dynamic>?)?[currentUserId] as num?)?.toInt() ?? 0;
              final messages = tripChat['messages'] as Map<dynamic, dynamic>?;
              if (messages == null) continue;
              for (final msgData in messages.values) {
                final msg = msgData as Map<dynamic, dynamic>;
                final timestamp = (msg['timestamp'] as num?)?.toInt() ?? 0;
                if (timestamp <= clearedAt) continue;
                if (msg['isSystemMessage'] == true) continue;
                final status = msg['status']?.toString() ?? 'sent';
                if (msg['senderId'] != currentUserId && status != 'read') {
                  totalUnread++;
                }
              }
            }

            if (totalUnread == 0) return child;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                child,
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      totalUnread > 99 ? '99+' : totalUnread.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
