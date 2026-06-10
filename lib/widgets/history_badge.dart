import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class HistoryBadge extends StatelessWidget {
  final Widget child;

  const HistoryBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return child;

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref()
          .child('bookings')
          .child(currentUserId)
          .onValue,
      builder: (context, snapshotBookings) {
        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref()
              .child('forgottenItems')
              .onValue,
          builder: (context, snapshotItems) {
            int totalUnseen = 0;

            if (snapshotBookings.hasData && snapshotBookings.data?.snapshot.value != null) {
              final data = snapshotBookings.data!.snapshot.value as Map<dynamic, dynamic>;
              data.forEach((key, value) {
                if (value is Map && value['passengerSeen'] == false) {
                  totalUnseen++;
                }
              });
            }

            if (snapshotItems.hasData && snapshotItems.data?.snapshot.value != null) {
              final data = snapshotItems.data!.snapshot.value as Map<dynamic, dynamic>;
              data.forEach((driverId, driverItems) {
                if (driverItems is Map) {
                  driverItems.forEach((itemId, item) {
                    if (item is Map && item['passengerId'] == currentUserId && item['passengerSeen'] == false) {
                      totalUnseen++;
                    }
                  });
                }
              });
            }

            if (totalUnseen == 0) return child;

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
                      totalUnseen > 99 ? '99+' : totalUnseen.toString(),
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
