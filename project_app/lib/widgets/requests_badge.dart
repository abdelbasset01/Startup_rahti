import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class RequestsBadge extends StatelessWidget {
  final Widget child;

  const RequestsBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return child;

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref()
          .child('trips')
          .orderByChild('driverId')
          .equalTo(currentUserId)
          .onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return child;
        }

        int totalUnseen = 0;
        final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

        data.forEach((tripKey, tripValue) {
          if (tripValue is! Map<dynamic, dynamic>) return;
          final takenSeats = tripValue['takenSeats'];

          if (takenSeats is Map<dynamic, dynamic>) {
            takenSeats.forEach((seatKey, seatValue) {
              if (seatValue is! Map<dynamic, dynamic>) return;
              final status = seatValue['status']?.toString() ?? 'booked';
              if ((status == 'booked' || status == 'pending' || status == 'passenger_countered') && (seatValue['driverSeen'] == false || seatValue['driverSeen'] == null)) {
                totalUnseen++;
              }
            });
          }
        });

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
  }
}
